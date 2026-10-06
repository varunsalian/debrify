import 'dart:async';

import 'package:debrify/features/stremio_tv/application/stremio_tv_stream_quality.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_bindings.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_owners.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_sections.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/stream_url_validator.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:debrify/utils/stremio_tv_debrid_fallback.dart';
import 'package:debrify/utils/torrent_coverage_detector.dart';
import 'package:debrify/widgets/pipeline_loading_overlay.dart';
import 'package:flutter/material.dart';

class StremioTvStreamSelection {
  StremioTvStreamSelection(this._deps);
  final StremioTvDependencies _deps;
  StremioTvOwners get _owners => _deps.owners;
  StremioTvSections get _sections => _deps.sections;
  // ============================================================================
  // Playback
  // ============================================================================
  /// Sort streams so those matching [_preferredQuality] come first.
  /// Within same-quality group, preserves original order.
  Future<({String url, int index})?> tryDirectStreams(
    List<Torrent> playableSources,
    int myGeneration,
  ) async {
    final directStreams = _sections.streams._sortStreamsByQuality(
      playableSources.where((t) => t.isDirectStream).toList(),
    );
    final maxDirectAttempts = directStreams.length.clamp(0, 20);
    for (int d = 0; d < maxDirectAttempts; d++) {
      final stream = directStreams[d];
      if (stream.directUrl == null || stream.directUrl!.isEmpty) continue;
      if (!_deps.mounted() || _owners.playback.playGeneration != myGeneration)
        return null;
      final valid = await _sections.streams.isValidStreamUrl(stream.directUrl!);
      if (!_deps.mounted() || _owners.playback.playGeneration != myGeneration)
        return null;
      if (valid) {
        final index = playableSources.indexWhere(
          (t) => t.directUrl == stream.directUrl && t.name == stream.name,
        );
        return (url: stream.directUrl!, index: index < 0 ? 0 : index);
      }
      debugPrint('StremioTV: Skipping invalid direct stream: ${stream.source}');
    }
    return null;
  }

  Future<({String url, int index})?> tryTorrentsViaDebrid(
    List<Torrent> playableSources,
    StremioMeta item,
    int myGeneration, {
    int? season,
    int? episode,
  }) async {
    final torrentStreams = _sections.streams._sortStreamsByQuality(
      playableSources.where((t) => t.streamType == StreamType.torrent).toList(),
    );
    final maxTorrentAttempts = torrentStreams.length.clamp(0, 20);
    final attemptedTorrents = torrentStreams.take(maxTorrentAttempts).toList();
    final loadAutoTorboxCachedHashes =
        StremioTvDebridFallback.memoizeAsync<Set<String>>(
          () => _sections.debrid.loadTorboxCachedHashes(
            attemptedTorrents,
            isCancelled: () =>
                !_deps.mounted() ||
                _owners.playback.playGeneration != myGeneration,
          ),
        );

    for (int i = 0; i < maxTorrentAttempts; i++) {
      if (!_deps.mounted() || _owners.playback.playGeneration != myGeneration)
        return null;
      final url = await _sections.debrid.resolveTorrentUrl(
        torrentStreams[i],
        item,
        _owners.settings.debridProvider,
        season: season,
        episode: episode,
        isCancelled: () =>
            !_deps.mounted() || _owners.playback.playGeneration != myGeneration,
        loadAutoTorboxCachedHashes: _owners.settings.debridProvider == 'auto'
            ? loadAutoTorboxCachedHashes
            : null,
      );
      if (url != null && url.isNotEmpty) {
        final index = playableSources.indexWhere(
          (t) =>
              t.infohash == torrentStreams[i].infohash &&
              t.name == torrentStreams[i].name,
        );
        return (url: url, index: index < 0 ? 0 : index);
      }
      debugPrint(
        'StremioTV: Torrent ${i + 1}/$maxTorrentAttempts failed, '
        '${i + 1 < maxTorrentAttempts ? "trying next..." : "giving up."}',
      );
    }
    return null;
  }

  /// Filters torrent candidates down to those that can actually provide the
  /// requested [season]/[episode]:
  ///  - non-torrent streams (direct/addon) pass through — they were queried
  ///    per-episode already;
  ///  - season/multi-season/complete packs are kept when they cover the target
  ///    season (or their range is unknown, in which case in-pack file
  ///    selection picks the episode);
  ///  - single-episode torrents are dropped only when we CONFIDENTLY parse a
  ///    different S/E from the name; ambiguous/unparseable names are kept.
  ///
  /// If every candidate is confidently a different episode this can return no
  /// torrents — that is intentional (see note at the return).
  List<Torrent> filterTorrentsForEpisode(
    List<Torrent> sources, {
    required int season,
    required int episode,
  }) {
    final kept = <Torrent>[];
    for (final t in sources) {
      if (t.streamType != StreamType.torrent) {
        kept.add(t);
        continue;
      }
      final coverage = TorrentCoverageDetector.detectCoverage(
        title: t.name,
        infohash: t.infohash,
      );
      switch (coverage.coverageType) {
        case CoverageType.completeSeries:
          kept.add(t);
          break;
        case CoverageType.multiSeasonPack:
          if (coverage.startSeason == null ||
              coverage.endSeason == null ||
              (season >= coverage.startSeason! &&
                  season <= coverage.endSeason!)) {
            kept.add(t);
          }
          break;
        case CoverageType.seasonPack:
          if (coverage.seasonNumber == null ||
              coverage.seasonNumber == season) {
            kept.add(t);
          }
          break;
        case CoverageType.singleEpisode:
          final info = SeriesParser.parseFilename(t.name);
          // Only drop when we're CONFIDENT it's a different episode — i.e. both
          // season and episode parsed and at least one differs. Ambiguous /
          // unparseable names are kept (could be the right episode with odd
          // naming, or a pack we failed to classify).
          final confidentMismatch =
              info.season != null &&
              info.episode != null &&
              (info.season != season || info.episode != episode);
          if (!confidentMismatch) {
            kept.add(t);
          }
          break;
      }
    }

    // NOTE: we intentionally do NOT fall back to the unfiltered set when this
    // leaves zero torrents. Zero here means every candidate confidently parsed
    // to a *different* episode, so falling back would replay the exact bug this
    // filter exists to fix. Returning the filtered set lets resolution use any
    // per-episode direct streams, or fail so the next-provider advances to a
    // slot/episode we can actually play correctly.
    return kept;
  }

  List<Torrent> _sortStreamsByQuality(List<Torrent> streams) {
    if (_owners.settings.preferredQuality == 'auto') return streams;
    final sorted = List<Torrent>.from(streams);
    sorted.sort((a, b) {
      final qa = StremioTvStreamQuality.extractQuality(a.name);
      final qb = StremioTvStreamQuality.extractQuality(b.name);
      final aMatch = qa == _owners.settings.preferredQuality ? 0 : 1;
      final bMatch = qb == _owners.settings.preferredQuality ? 0 : 1;
      return aMatch.compareTo(bMatch);
    });
    return sorted;
  }

  /// Direct-stream validity: delegated to the shared [StreamUrlValidator]
  /// (extracted from this screen so quick-play uses the identical check).
  Future<bool> isValidStreamUrl(String url) =>
      StreamUrlValidator.isPlayableVideoUrl(url);

  /// Maps the active debrid provider to the Pipeline loader's chip label,
  /// two-letter code, accent colour, and whether it runs a cache-check stage.
  /// Colours mirror the Home/Search play loader (torrent_playback_service).
  ({String label, String code, Color color, bool cacheCheck}) tvProviderInfo() {
    switch (_owners.settings.debridProvider) {
      case 'realdebrid':
        return (
          label: 'Real-Debrid',
          code: 'RD',
          color: const Color(0xFF10B981),
          cacheCheck: false,
        );
      case 'torbox':
        return (
          label: 'TorBox',
          code: 'TB',
          color: const Color(0xFF8B5CF6),
          cacheCheck: true,
        );
      case 'premiumize':
        return (
          label: 'Premiumize',
          code: 'PM',
          color: const Color(0xFFF59E0B),
          cacheCheck: true,
        );
      case 'alldebrid':
        return (
          label: 'AllDebrid',
          code: 'AD',
          color: const Color(0xFF26A69A),
          cacheCheck: false,
        );
      case 'pikpak':
        return (
          label: 'PikPak',
          code: 'PP',
          color: const Color(0xFF6366F1),
          cacheCheck: false,
        );
      default:
        return (
          label: 'Debrid',
          code: 'DB',
          color: PipelineLoadingOverlay.accent,
          cacheCheck: false,
        );
    }
  }
}
