import 'dart:async';

import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_bindings.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_owners.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_sections.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/alldebrid_service.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/pikpak_storage.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/services/torbox_service.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/rd_blocked_filter.dart';
import 'package:debrify/utils/stremio_episode_selector.dart';
import 'package:debrify/utils/stremio_tv_debrid_fallback.dart';
import 'package:flutter/material.dart';

class StremioTvDebridResolvers {
  StremioTvDebridResolvers(this._deps);
  final StremioTvDependencies _deps;
  StremioTvOwners get _owners => _deps.owners;
  StremioTvSections get _sections => _deps.sections;

  /// Resolve a torrent to a playable URL via the given debrid provider.
  Future<String?> resolveTorrentUrl(
    Torrent torrent,
    StremioMeta item,
    String debridProvider, {
    int? season,
    int? episode,
    bool Function()? isCancelled,
    Future<Set<String>> Function()? loadAutoTorboxCachedHashes,
  }) => StremioTvDebridFallback.resolve<String>(
    selected: debridProvider,
    isCancelled: isCancelled,
    canAttempt: (provider) async {
      switch (provider) {
        case 'realdebrid':
          return !_owners.settings.rdSkipBlockedTorrents ||
              !isRdBlockedTorrent(torrent.name);
        case 'torbox':
          if (debridProvider != 'auto') return true;
          final cachedHashes = loadAutoTorboxCachedHashes != null
              ? await loadAutoTorboxCachedHashes()
              : await _sections.debrid.loadTorboxCachedHashes(<Torrent>[
                  torrent,
                ], isCancelled: isCancelled);
          return cachedHashes.contains(torrent.infohash.trim().toLowerCase());
        case 'premiumize':
          return PremiumizeStorage.getPremiumizeIntegrationEnabled();
        case 'alldebrid':
          return AllDebridStorage.getAllDebridIntegrationEnabled();
        default:
          return true;
      }
    },
    attempt: (provider) async {
      switch (provider) {
        case 'realdebrid':
          final apiKey = await RealDebridStorage.getApiKey();
          if (apiKey == null || apiKey.isEmpty) return null;
          return _sections.debrid._resolveViaRealDebrid(
            torrent,
            item,
            apiKey,
            season: season,
            episode: episode,
          );
        case 'torbox':
          final apiKey = await TorboxStorage.getTorboxApiKey();
          if (apiKey == null || apiKey.isEmpty) return null;
          return _sections.cloud.resolveViaTorbox(
            torrent,
            item,
            apiKey,
            season: season,
            episode: episode,
            isCancelled: isCancelled,
          );
        case 'pikpak':
          if (!await PikpakStorage.getPikPakEnabled()) return null;
          return _sections.cloud.resolveViaPikPak(
            torrent,
            item,
            season: season,
            episode: episode,
            isCancelled: isCancelled,
          );
        case 'premiumize':
          final apiKey = await PremiumizeStorage.getPremiumizeApiKey();
          if (apiKey == null || apiKey.isEmpty) return null;
          return _sections.cloud.resolveViaPremiumize(
            torrent,
            item,
            apiKey,
            season: season,
            episode: episode,
          );
        case 'alldebrid':
          final apiKey = await AllDebridStorage.getAllDebridApiKey();
          if (apiKey == null || apiKey.isEmpty) return null;
          return _sections.debrid._resolveViaAllDebrid(
            torrent,
            item,
            apiKey,
            season: season,
            episode: episode,
          );
      }
      return null;
    },
  );

  Future<Set<String>> loadTorboxCachedHashes(
    Iterable<Torrent> torrents, {
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() ?? false) return const <String>{};

    final apiKey = await TorboxStorage.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty || (isCancelled?.call() ?? false)) {
      return const <String>{};
    }

    final infoHashes = torrents
        .map((torrent) => torrent.infohash.trim().toLowerCase())
        .where((hash) => hash.isNotEmpty)
        .toSet()
        .toList();
    if (infoHashes.isEmpty) return const <String>{};

    try {
      final cachedHashes = await TorboxService.checkCachedTorrents(
        apiKey: apiKey,
        infoHashes: infoHashes,
      );
      if (isCancelled?.call() ?? false) return const <String>{};

      final normalized = cachedHashes
          .map((hash) => hash.trim().toLowerCase())
          .where((hash) => hash.isNotEmpty)
          .toSet();
      debugPrint(
        'StremioTV: Auto TorBox cache check found ${normalized.length} '
        'of ${infoHashes.length} candidate(s)',
      );
      return normalized;
    } catch (e) {
      debugPrint('StremioTV: TorBox cache check failed: $e');
      return const <String>{};
    }
  }

  Future<String?> _resolveViaRealDebrid(
    Torrent torrent,
    StremioMeta item,
    String apiKey, {
    int? season,
    int? episode,
  }) async {
    try {
      final magnet =
          'magnet:?xt=urn:btih:${torrent.infohash}&dn=${Uri.encodeComponent(torrent.name)}';
      final result = await DebridService.addTorrentToDebridPreferVideos(
        apiKey,
        magnet,
      );

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

      final isSeries = item.type.toLowerCase() == 'series';
      if (isSeries && season != null && episode != null) {
        final candidateNames = selectedVideoFiles.map((file) {
          return (file['path'] as String?) ?? (file['name'] as String?) ?? '';
        }).toList();
        final targetIndex =
            StremioEpisodeSelector.findEpisodeFileIndexWithSingleFileFallback(
              candidateNames,
              sourceName: torrent.name,
              season: season,
              episode: episode,
            );
        if (targetIndex == null || targetIndex >= selectedVideoLinks.length) {
          debugPrint(
            'StremioTV: RD could not match S${season}E$episode in ${torrent.name}, '
            'rejecting source',
          );
          final torrentId = result['torrentId']?.toString();
          if (torrentId != null && torrentId.isNotEmpty) {
            try {
              await DebridService.deleteTorrent(apiKey, torrentId);
            } catch (_) {}
          }
          return null;
        } else {
          linkToUnrestrict = selectedVideoLinks[targetIndex];
        }
      } else if (item.type.toLowerCase() == 'movie' &&
          selectedVideoLinks.length > 1) {
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
      return unrestrictResult['download'] as String?;
    } catch (e) {
      debugPrint('StremioTV: RD resolve error: $e');
      return null;
    }
  }

  /// Resolves a torrent to a playable URL via AllDebrid. Follows the
  /// Real-Debrid model (no cache-check API): adds the magnet trusting the
  /// `ready` flag (no polling), and on not-ready deletes the magnet and
  /// returns null so the caller probes the next source. Picks the episode
  /// (series) or largest file (movie), then unlocks that locked link.
  Future<String?> _resolveViaAllDebrid(
    Torrent torrent,
    StremioMeta item,
    String apiKey, {
    int? season,
    int? episode,
  }) async {
    try {
      final magnet =
          'magnet:?xt=urn:btih:${torrent.infohash}&dn=${Uri.encodeComponent(torrent.name)}';
      AllDebridAddResult result;
      try {
        result = await AllDebridService.addMagnetAndResolveFiles(
          apiKey,
          magnet,
        );
      } on AllDebridTorrentNotReadyException catch (e) {
        // Not cached/ready — don't leave it downloading on the account.
        await AllDebridService.deleteMagnet(e.apiKey, e.magnetId);
        return null;
      }

      final videoFiles = result.files
          .where((f) => FileUtils.isVideoFile(f.fileName))
          .toList();
      if (videoFiles.isEmpty) return null;

      String targetLink = videoFiles.first.link;

      final isSeries = item.type.toLowerCase() == 'series';
      if (isSeries && season != null && episode != null) {
        final candidateNames = videoFiles.map((f) => f.path).toList();
        final targetIndex =
            StremioEpisodeSelector.findEpisodeFileIndexWithSingleFileFallback(
              candidateNames,
              sourceName: torrent.name,
              season: season,
              episode: episode,
            );
        if (targetIndex == null || targetIndex >= videoFiles.length) {
          debugPrint(
            'StremioTV: AllDebrid could not match S${season}E$episode in '
            '${torrent.name}, rejecting source',
          );
          try {
            await AllDebridService.deleteMagnet(apiKey, result.magnetId);
          } catch (_) {}
          return null;
        } else {
          targetLink = videoFiles[targetIndex].link;
        }
      } else if (item.type.toLowerCase() == 'movie' && videoFiles.length > 1) {
        final targetIndex = StremioEpisodeSelector.findLargestFileIndex(
          videoFiles.map<int?>((f) => f.size).toList(),
        );
        if (targetIndex < videoFiles.length) {
          targetLink = videoFiles[targetIndex].link;
        }
      }

      if (targetLink.isEmpty) return null;
      final url = await AllDebridService.unlockLink(apiKey, targetLink);
      return url.isEmpty ? null : url;
    } catch (e) {
      debugPrint('StremioTV: AllDebrid resolve error: $e');
      return null;
    }
  }
}
