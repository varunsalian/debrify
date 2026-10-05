import 'dart:async';
import 'dart:math';

import 'package:debrify/features/debrify_tv/models/debrify_tv_constants.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/models/debrify_tv/cache_results.dart';
import 'package:debrify/models/debrify_tv/prepared_torrents.dart';
import 'package:debrify/models/premiumize_file.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/pikpak_api_service.dart';
import 'package:debrify/services/pikpak_tv_service.dart';
import 'package:debrify/services/premiumize_service.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DebrifyTvCloudResolvers {
  final DebrifyTvDependencies _deps;
  DebrifyTvCloudResolvers(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  Future<PikPakPreparedTorrent?> preparePikPakTorrent({
    required Torrent candidate,
    required void Function(String message) log,
  }) async {
    final infohash = _sections.filters.normalizeInfohash(candidate.infohash);
    if (infohash.isEmpty) {
      return null;
    }

    log('⏳ PikPak: preparing ${candidate.name}');

    final prepared = await PikPakTvService.instance.prepareTorrent(
      infohash: infohash,
      torrentName: candidate.name,
      onLog: log,
    );

    if (prepared == null) {
      log('⚠️ PikPak torrent not ready ${candidate.name}');
      return null;
    }

    // Check if this is a multi-file torrent
    final allVideoFiles = prepared['allVideoFiles'] as List<dynamic>?;

    if (allVideoFiles == null || allVideoFiles.isEmpty) {
      // Single file torrent - return directly
      log('🎬 PikPak: streaming ${prepared['title']}');
      return PikPakPreparedTorrent(
        streamUrl: prepared['url'] as String,
        title: prepared['title'] as String,
        hasMore: false,
      );
    }

    // Multi-file torrent - filter out seen files
    final pikpakFolderId = prepared['pikpakFolderId'] as String?;
    if (pikpakFolderId == null) {
      log('⚠️ PikPak multi-file torrent missing folder ID');
      return null;
    }

    // Filter unseen files. PikPak reports a per-file `size`, so the same
    // per-FILE size rules the other providers use apply here — including the
    // 50MB floor that keeps trailers and samples out of the rotation.
    List<dynamic> filterUnseen({required bool applySizeFilter}) {
      return allVideoFiles.where((file) {
        final fileId = file['id'] as String?;
        if (fileId == null || fileId.isEmpty) return false;
        final trackingKey = '$infohash|$fileId';
        if (_owners.session.seenLinkWithTorrentId.contains(trackingKey))
          return false;
        final size = (file['size'] as num?)?.toInt() ?? 0;
        if (size > 0 && size < DebrifyTvConstants.torboxMinVideoSizeBytes)
          return false;
        if (applySizeFilter &&
            !_owners.settings.tvFilters.sizeMatchesBytes(size))
          return false;
        return true;
      }).toList();
    }

    var unseenFiles = filterUnseen(applySizeFilter: true);
    if (unseenFiles.isEmpty && _owners.settings.tvFilters.hasSize) {
      // Nothing in this torrent matched — take it unfiltered rather than
      // discarding the torrent (see the Torbox builder).
      log('⚠️ PikPak: no file matched the size filter — using unfiltered');
      unseenFiles = filterUnseen(applySizeFilter: false);
    }

    if (unseenFiles.isEmpty) {
      log('⚠️ PikPak torrent has no unseen files ${candidate.name}');
      return null;
    }

    // Shuffle and select next file
    final random = Random();
    unseenFiles.shuffle(random);
    final selectedFile = unseenFiles.removeAt(0);
    final selectedFileId = selectedFile['id'] as String?;
    final selectedFileName = selectedFile['name'] as String?;

    if (selectedFileId == null ||
        selectedFileId.isEmpty ||
        selectedFileName == null ||
        selectedFileName.isEmpty) {
      log('⚠️ Selected file has invalid ID or name');
      return null;
    }

    log(
      '🎬 PikPak: selected $selectedFileName (${unseenFiles.length} unseen files)',
    );

    // Get streaming URL for selected file
    String streamUrl;
    try {
      final api = PikPakApiService.instance;
      final fullFileData = await api.getFileDetails(selectedFileId);
      final url = api.getStreamingUrl(fullFileData);
      if (url == null || url.isEmpty) {
        log('⚠️ No streaming URL for selected file');
        return null;
      }
      streamUrl = url;
    } catch (e) {
      log('❌ Failed to get streaming URL: $e');
      return null;
    }

    // Mark as seen
    _owners.session.seenLinkWithTorrentId.add('$infohash|$selectedFileId');

    return PikPakPreparedTorrent(
      streamUrl: streamUrl,
      title: selectedFileName,
      hasMore: unseenFiles.isNotEmpty,
    );
  }
  // ── Premiumize helpers ──────────────────────────────────────────────────────

  Future<TorboxCacheWindowResult> fetchPremiumizeCacheWindow({
    required List<Torrent> candidates,
    required int startIndex,
    required String apiKey,
  }) async {
    const int chunkSize = 100;
    const int maxCalls = 2;

    int cursor = startIndex;
    int calls = 0;
    final List<Torrent> hits = [];

    while (cursor < candidates.length && calls < maxCalls && hits.isEmpty) {
      final int end = min(cursor + chunkSize, candidates.length);
      final List<Torrent> chunk = candidates.sublist(cursor, end);
      cursor = end;

      final List<Torrent> validChunk = chunk
          .where(
            (t) => _sections.filters.normalizeInfohash(t.infohash).isNotEmpty,
          )
          .toList();
      final List<String> hashes = validChunk
          .map((t) => _sections.filters.normalizeInfohash(t.infohash))
          .toList();

      if (hashes.isEmpty) continue;

      calls++;
      final List<bool> cached = await PremiumizeService.checkCache(
        apiKey,
        hashes,
      );

      for (int i = 0; i < validChunk.length; i++) {
        if (i < cached.length && cached[i]) {
          hits.add(validChunk[i]);
        }
      }
    }

    return TorboxCacheWindowResult(
      cachedTorrents: hits,
      nextCursor: cursor,
      exhausted: cursor >= candidates.length,
    );
  }

  Future<PremiumizePreparedTorrent?> preparePremiumizeTorrent({
    required Torrent candidate,
    required String apiKey,
    required void Function(String message) log,
  }) async {
    final infohash = _sections.filters.normalizeInfohash(candidate.infohash);
    if (infohash.isEmpty) return null;

    log('⏳ Premiumize: preparing ${candidate.name}');

    final magnet = 'magnet:?xt=urn:btih:${candidate.infohash}';
    List<PremiumizeFile> files;
    try {
      files = await PremiumizeService.directDownload(apiKey, magnet);
    } catch (e) {
      log('❌ Premiumize directdl failed: $e');
      return null;
    }

    if (files.isEmpty) {
      log('⚠️ Premiumize: no files for ${candidate.name}');
      return null;
    }

    final playableEntries = _sections.cloud._buildPremiumizePlayableEntries(
      files,
      candidate.name,
    );
    if (playableEntries.isEmpty) {
      log('⚠️ Premiumize: no playable files for ${candidate.name}');
      return null;
    }

    final filteredEntries = playableEntries
        .where(
          (e) => !_owners.session.seenLinkWithTorrentId.contains(
            '$infohash|${e.file.path}',
          ),
        )
        .toList();
    if (filteredEntries.isEmpty) {
      log('⚠️ Premiumize: no unseen playable files for ${candidate.name}');
      return null;
    }

    filteredEntries.shuffle(Random());
    final next = filteredEntries.removeAt(0);
    final streamUrl = next.file.streamLink ?? next.file.link;
    _owners.session.seenLinkWithTorrentId.add('$infohash|${next.file.path}');
    log('🎬 Premiumize: streaming ${next.title}');
    return PremiumizePreparedTorrent(
      streamUrl: streamUrl,
      title: next.title,
      hasMore: filteredEntries.isNotEmpty,
    );
  }

  List<PremiumizePlayableEntry> _buildPremiumizePlayableEntries(
    List<PremiumizeFile> files,
    String fallbackTitle, {
    bool applySizeFilter = true,
  }) {
    final seriesCandidates = <PremiumizePlayableEntry>[];
    final otherCandidates = <PremiumizePlayableEntry>[];

    for (final file in files) {
      if (!_sections.cloud._premiumizeFileLooksLikeVideo(file)) continue;
      if (file.size < DebrifyTvConstants.torboxMinVideoSizeBytes) continue;
      // Per-FILE size filter (see the Torbox builder for the rationale).
      if (applySizeFilter &&
          !_owners.settings.tvFilters.sizeMatchesBytes(file.size))
        continue;

      final displayName = file.fileName.isNotEmpty
          ? file.fileName
          : fallbackTitle;
      final info = SeriesParser.parseFilenameConservative(displayName);
      final title = info.isSeries
          ? _sections.torbox.formatTorboxSeriesTitle(info, fallbackTitle)
          : (displayName.isNotEmpty ? displayName : fallbackTitle);
      final entry = PremiumizePlayableEntry(
        file: file,
        title: title,
        info: info,
      );

      if (info.isSeries && info.season != null && info.episode != null) {
        seriesCandidates.add(entry);
      } else {
        otherCandidates.add(entry);
      }
    }

    seriesCandidates.sort((a, b) {
      final seasonCompare = (a.info.season ?? 0).compareTo(b.info.season ?? 0);
      if (seasonCompare != 0) return seasonCompare;
      return (a.info.episode ?? 0).compareTo(b.info.episode ?? 0);
    });

    otherCandidates.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );

    final entries = <PremiumizePlayableEntry>[
      ...seriesCandidates,
      ...otherCandidates,
    ];
    entries.shuffle(Random());
    if (entries.isEmpty &&
        applySizeFilter &&
        _owners.settings.tvFilters.hasSize) {
      debugPrint(
        'DebrifyTV/Premiumize: no file matched the size filter in '
        '"$fallbackTitle" — using it unfiltered.',
      );
      return _sections.cloud._buildPremiumizePlayableEntries(
        files,
        fallbackTitle,
        applySizeFilter: false,
      );
    }
    return entries;
  }

  bool _premiumizeFileLooksLikeVideo(PremiumizeFile file) {
    final name = file.fileName;
    if (name.isEmpty) return false;
    return FileUtils.isVideoFile(name);
  }
}
