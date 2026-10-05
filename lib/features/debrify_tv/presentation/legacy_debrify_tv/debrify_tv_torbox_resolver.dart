import 'dart:async';
import 'dart:math';

import 'package:debrify/features/debrify_tv/models/debrify_tv_constants.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/models/debrify_tv/cache_results.dart';
import 'package:debrify/models/debrify_tv/prepared_torrents.dart';
import 'package:debrify/models/torbox_file.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/torbox_service.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DebrifyTvTorboxResolver {
  final DebrifyTvDependencies _deps;
  DebrifyTvTorboxResolver(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  Future<TorboxCacheWindowResult> fetchTorboxCacheWindow({
    required List<Torrent> candidates,
    required int startIndex,
    required String apiKey,
  }) async {
    const int chunkSize = 90;
    const int maxCalls = 2;

    int cursor = startIndex;
    int calls = 0;
    final List<Torrent> hits = <Torrent>[];

    while (cursor < candidates.length && calls < maxCalls && hits.isEmpty) {
      final int end = min(cursor + chunkSize, candidates.length);
      final List<Torrent> chunk = candidates.sublist(cursor, end);
      cursor = end;

      final List<String> hashes = chunk
          .map(
            (torrent) => _sections.filters.normalizeInfohash(torrent.infohash),
          )
          .where((hash) => hash.isNotEmpty)
          .toList();

      if (hashes.isEmpty) {
        continue;
      }

      calls += 1;
      final Set<String> cachedHashes = await TorboxService.checkCachedTorrents(
        apiKey: apiKey,
        infoHashes: hashes,
        listFiles: false,
      );

      if (cachedHashes.isEmpty) {
        continue;
      }

      final Set<String> normalized = cachedHashes
          .map((hash) => hash.trim().toLowerCase())
          .where((hash) => hash.isNotEmpty)
          .toSet();

      hits.addAll(
        chunk.where(
          (torrent) => normalized.contains(
            _sections.filters.normalizeInfohash(torrent.infohash),
          ),
        ),
      );
    }

    final bool exhausted = cursor >= candidates.length;
    return TorboxCacheWindowResult(
      cachedTorrents: hits,
      nextCursor: cursor,
      exhausted: exhausted,
    );
  }

  Future<Map<String, String>?> resolveTorboxQueuedFile({
    required Map<String, dynamic> entry,
    required String apiKey,
    required void Function(String message) log,
  }) async {
    final torrentId = entry['torrentId'] as int?;
    final TorboxFile? file = entry['file'] as TorboxFile?;
    final String? title = entry['title'] as String?;
    if (torrentId == null || file == null) {
      return null;
    }
    try {
      final streamUrl = await TorboxService.requestFileDownloadLink(
        apiKey: apiKey,
        torrentId: torrentId,
        fileId: file.id,
      );
      final resolvedTitle = title ?? _sections.torbox._torboxDisplayName(file);
      log('➡️ Torbox: streaming $resolvedTitle');
      return {'url': streamUrl, 'title': resolvedTitle};
    } catch (e) {
      log('❌ Torbox stream failed: $e');
      return null;
    }
  }

  Future<TorboxPreparedTorrent?> prepareTorboxTorrent({
    required Torrent candidate,
    required String apiKey,
    required void Function(String message) log,
  }) async {
    final infohash = _sections.filters.normalizeInfohash(candidate.infohash);
    if (infohash.isEmpty) {
      return null;
    }

    log('⏳ Torbox: preparing ${candidate.name}');

    final magnetLink = 'magnet:?xt=urn:btih:${candidate.infohash}';
    Map<String, dynamic> response;
    try {
      response = await TorboxService.createTorrent(
        apiKey: apiKey,
        magnet: magnetLink,
        seed: true,
        allowZip: false,
        addOnlyIfCached: true,
      );
    } catch (e) {
      log('❌ Torbox createtorrent failed: $e');
      return null;
    }

    final success = response['success'] as bool? ?? false;
    if (!success) {
      final error = (response['error'] ?? '').toString();
      log('⚠️ Torbox createtorrent error: $error');
      return null;
    }

    final data = response['data'];
    final torrentId = _sections.torbox._asIntMapValue(data, 'torrent_id');
    if (torrentId == null) {
      log('⚠️ Torbox createtorrent missing torrent_id');
      return null;
    }

    TorboxTorrent? torboxTorrent;
    for (int attempt = 0; attempt < 6; attempt++) {
      torboxTorrent = await TorboxService.getTorrentById(
        apiKey,
        torrentId,
        attempts: 1,
      );
      if (torboxTorrent != null && torboxTorrent.files.isNotEmpty) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }

    if (torboxTorrent == null || torboxTorrent.files.isEmpty) {
      log('⚠️ Torbox torrent details not ready for ${candidate.name}');
      return null;
    }

    final currentTorrent = torboxTorrent;

    final playableEntries = _sections.torbox._buildTorboxPlayableEntries(
      currentTorrent,
      candidate.name,
    );
    if (playableEntries.isEmpty) {
      log('⚠️ Torbox torrent has no playable files ${candidate.name}');
      return null;
    }

    final random = Random();
    final filteredEntries = playableEntries
        .where(
          (entry) => !_owners.session.seenLinkWithTorrentId.contains(
            '${currentTorrent.id}|${entry.file.id}',
          ),
        )
        .toList();
    if (filteredEntries.isEmpty) {
      log('⚠️ Torbox torrent has no unseen playable files ${candidate.name}');
      return null;
    }

    filteredEntries.shuffle(random);
    final next = filteredEntries.removeAt(0);
    try {
      final streamUrl = await TorboxService.requestFileDownloadLink(
        apiKey: apiKey,
        torrentId: currentTorrent.id,
        fileId: next.file.id,
      );
      log('🎬 Torbox: streaming ${next.title}');
      _owners.session.seenLinkWithTorrentId.add(
        '${currentTorrent.id}|${next.file.id}',
      );
      return TorboxPreparedTorrent(
        streamUrl: streamUrl,
        title: next.title,
        hasMore: filteredEntries.isNotEmpty,
      );
    } catch (e) {
      log('❌ Torbox requestdl failed: $e');
      return null;
    }
  }

  List<TorboxPlayableEntry> _buildTorboxPlayableEntries(
    TorboxTorrent torrent,
    String fallbackTitle, {
    bool applySizeFilter = true,
  }) {
    final entries = <TorboxPlayableEntry>[];
    final seriesCandidates = <TorboxPlayableEntry>[];
    final otherCandidates = <TorboxPlayableEntry>[];

    for (final file in torrent.files) {
      if (!_sections.torbox._torboxFileLooksLikeVideo(file)) continue;
      if (file.size < DebrifyTvConstants.torboxMinVideoSizeBytes) continue;
      // Per-FILE size filter: a pack's files are individual episodes, so this
      // compares against the number the user actually meant.
      if (applySizeFilter &&
          !_owners.settings.tvFilters.sizeMatchesBytes(file.size))
        continue;

      final displayName = _sections.torbox._torboxDisplayName(file);
      final info = SeriesParser.parseFilenameConservative(displayName);
      final title = info.isSeries
          ? _sections.torbox.formatTorboxSeriesTitle(info, fallbackTitle)
          : (displayName.isNotEmpty ? displayName : fallbackTitle);
      final entry = TorboxPlayableEntry(file: file, title: title, info: info);

      if (info.isSeries && info.season != null && info.episode != null) {
        seriesCandidates.add(entry);
      } else {
        otherCandidates.add(entry);
      }
    }

    // Sort series candidates by season and episode
    seriesCandidates.sort((a, b) {
      final seasonCompare = (a.info.season ?? 0).compareTo(b.info.season ?? 0);
      if (seasonCompare != 0) return seasonCompare;
      return (a.info.episode ?? 0).compareTo(b.info.episode ?? 0);
    });

    // Sort other candidates alphabetically
    otherCandidates.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );

    entries
      ..addAll(seriesCandidates)
      ..addAll(otherCandidates);
    entries.shuffle(Random());
    // Nothing in THIS torrent matched the size filter — take it unfiltered
    // rather than discarding the torrent, so a strict filter narrows what
    // plays instead of walking the whole queue and playing nothing.
    if (entries.isEmpty &&
        applySizeFilter &&
        _owners.settings.tvFilters.hasSize) {
      debugPrint(
        'DebrifyTV/Torbox: no file matched the size filter in '
        '"$fallbackTitle" — using it unfiltered.',
      );
      return _sections.torbox._buildTorboxPlayableEntries(
        torrent,
        fallbackTitle,
        applySizeFilter: false,
      );
    }
    return entries;
  }

  String formatTorboxSeriesTitle(SeriesInfo info, String fallback) {
    final season = info.season?.toString().padLeft(2, '0');
    final episode = info.episode?.toString().padLeft(2, '0');
    final descriptor = info.episodeTitle?.trim().isNotEmpty == true
        ? info.episodeTitle!.trim()
        : (info.title?.trim().isNotEmpty == true
              ? info.title!.trim()
              : fallback);
    if (season != null && episode != null) {
      return 'S${season}E$episode · $descriptor';
    }
    return fallback;
  }

  bool _torboxFileLooksLikeVideo(TorboxFile file) {
    if (file.zipped) return false;
    final name = file.shortName.isNotEmpty
        ? file.shortName
        : FileUtils.getFileName(file.name);
    if (FileUtils.isVideoFile(name)) return true;
    final mime = file.mimetype?.toLowerCase();
    return mime != null && mime.startsWith('video/');
  }

  String _torboxDisplayName(TorboxFile file) {
    if (file.shortName.isNotEmpty) {
      return file.shortName;
    }
    if (file.name.isNotEmpty) {
      return FileUtils.getFileName(file.name);
    }
    return 'File ${file.id}';
  }

  int? _asIntMapValue(dynamic data, String key) {
    if (data is Map<String, dynamic>) {
      final value = data[key];
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      if (value is num) return value.toInt();
    }
    return null;
  }

  String formatTorboxError(Object error) {
    return error.toString().replaceFirst('Exception: ', '').trim();
  }
}
