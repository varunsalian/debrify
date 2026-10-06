import 'dart:async';

import 'package:debrify/features/stremio_tv/application/stremio_tv_stream_quality.dart';
import 'package:debrify/features/stremio_tv/models/stremio_tv_playback_records.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_bindings.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_owners.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_sections.dart';
import 'package:debrify/features/stremio_tv/presentation/stremio_tv_manual_source_picker.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_channel.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/premiumize_service.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/services/torbox_service.dart';
import 'package:debrify/services/torrent_service.dart';
import 'package:flutter/material.dart';

class StremioTvChannelResolve {
  StremioTvChannelResolve(this._deps);
  final StremioTvDependencies _deps;
  StremioTvOwners get _owners => _deps.owners;
  StremioTvSections get _sections => _deps.sections;

  /// Resolves a channel to a playable URL without any UI interactions.
  /// Used by the in-player channel guide for background channel switching.
  Future<StremioTvChannelPlaybackResult?> resolveChannelPlayback(
    StremioTvChannel channel, {
    int slotOffset = 0,
  }) async {
    // Ensure items are loaded
    if (!channel.hasItems) {
      await _sections.library.ensureChannelItemsLoaded(channel);
    }

    final schedule = _owners.library.service.getSchedule(
      channel,
      count: slotOffset + 2,
      rotationMinutes: _sections.library.rotationFor(channel),
      salt: _owners.library.mixSalt,
    );
    if (schedule.length <= slotOffset) return null;

    final basePlaying = schedule.first;
    final nowPlaying = schedule[slotOffset];
    final nextPlaying = schedule.length > slotOffset + 1
        ? schedule[slotOffset + 1]
        : null;

    final item = nowPlaying.item;
    final slotProgress = _sections.resolve.computeStartProgress(
      channel.id,
      nowPlaying.progress,
    );

    if (!item.hasValidId) return null;

    // For series, resolve a random episode
    int? season;
    int? episode;
    if (item.type.toLowerCase() == 'series') {
      final episodeSeed = _owners.settings.randomEpisodes
          ? '${channel.id}:${DateTime.now().millisecondsSinceEpoch}'
          : '${channel.id}:${nowPlaying.slotStart.millisecondsSinceEpoch}';
      final resolved = await _owners.library.service.resolveRandomEpisode(
        item: item,
        addon: channel.addon,
        seed: episodeSeed,
      );
      if (resolved == null) return null;
      season = resolved.season;
      episode = resolved.episode;
    }

    final playTitle = season != null
        ? '${item.name} (S${season}E$episode)'
        : item.name;

    // Search streams (torrent engines + Stremio addons)
    final isMovie = item.type.toLowerCase() == 'movie';
    final results = await TorrentService.searchByImdbWithStremio(
      item.effectiveImdbId ?? item.id,
      includeMediaServers: false,
      isMovie: isMovie,
      season: season,
      episode: episode,
      contentType: item.type,
      stremioTimeout: const Duration(seconds: 7),
    );

    final torrents = results['torrents'] as List<Torrent>? ?? [];
    if (torrents.isEmpty) return null;

    // Filter sources — exclude 480p torrents (rarely cached on debrid)
    var playableSources = torrents
        .where((t) => !t.isExternalStream)
        .where((t) => !t.isDirectStream || t.sizeBytes >= 5 * 1024 * 1024)
        .where(
          (t) =>
              t.streamType != StreamType.torrent ||
              StremioTvStreamQuality.extractQuality(t.name) != '480p',
        )
        .toList();

    // Episode-match filter — many engines (e.g. apibay keyword search) return
    // single-episode torrents for the WRONG episode of the same series. Without
    // this, the highest-seeded unrelated episode wins auto-play and every slot
    // plays the same file. Keep exact-episode matches + season-covering packs,
    // drop single-episode torrents that belong to a different episode.
    if (!isMovie && season != null && episode != null) {
      playableSources = _sections.streams.filterTorrentsForEpisode(
        playableSources,
        season: season,
        episode: episode,
      );
    }

    // TorBox cache filter
    if (_owners.settings.debridProvider == 'torbox') {
      final tbKey = await TorboxStorage.getTorboxApiKey();
      if (tbKey != null && tbKey.isNotEmpty) {
        final torrentHashes = playableSources
            .where((t) => t.streamType == StreamType.torrent)
            .map((t) => t.infohash.trim().toLowerCase())
            .where((h) => h.isNotEmpty)
            .toList();
        if (torrentHashes.isNotEmpty) {
          final cachedHashes = await TorboxService.checkCachedTorrents(
            apiKey: tbKey,
            infoHashes: torrentHashes,
          );
          final cachedSet = cachedHashes
              .map((h) => h.trim().toLowerCase())
              .toSet();
          playableSources = playableSources
              .where(
                (t) =>
                    t.streamType != StreamType.torrent ||
                    cachedSet.contains(t.infohash.trim().toLowerCase()),
              )
              .toList();
        }
      }
    }

    // Premiumize cache filter
    if (_owners.settings.debridProvider == 'premiumize') {
      final pmKey = await PremiumizeStorage.getPremiumizeApiKey();
      if (pmKey != null && pmKey.isNotEmpty) {
        final torrentSources = playableSources
            .where((t) => t.streamType == StreamType.torrent)
            .toList();
        final torrentHashes = torrentSources
            .map((t) => t.infohash.trim().toLowerCase())
            .where((h) => h.isNotEmpty)
            .toList();
        if (torrentHashes.isNotEmpty) {
          final cachedResults = await PremiumizeService.checkCache(
            pmKey,
            torrentHashes,
          );
          final cachedSet = <String>{};
          for (int i = 0; i < torrentHashes.length; i++) {
            if (i < cachedResults.length && cachedResults[i]) {
              cachedSet.add(torrentHashes[i]);
            }
          }
          playableSources = playableSources
              .where(
                (t) =>
                    t.streamType != StreamType.torrent ||
                    cachedSet.contains(t.infohash.trim().toLowerCase()),
              )
              .toList();
        }
      }
    }

    if (playableSources.isEmpty) return null;

    // Auto-play best stream (respects torrents-first setting)
    final gen = _owners.playback.playGeneration;
    ({String url, int index})? resolved;
    if (_owners.settings.torrentsFirst) {
      resolved = await _sections.streams.tryTorrentsViaDebrid(
        playableSources,
        item,
        gen,
        season: season,
        episode: episode,
      );
      resolved ??= await _sections.streams.tryDirectStreams(
        playableSources,
        gen,
      );
    } else {
      resolved = await _sections.streams.tryDirectStreams(playableSources, gen);
      resolved ??= await _sections.streams.tryTorrentsViaDebrid(
        playableSources,
        item,
        gen,
        season: season,
        episode: episode,
      );
    }

    if (resolved == null) return null;

    final firstPlayableUrl = resolved.url;
    final firstPlayableIndex = resolved.index;

    final title = season != null
        ? '${item.name} (S${season}E$episode)'
        : playTitle;

    return StremioTvChannelPlaybackResult(
      url: firstPlayableUrl,
      title: title,
      contentType: item.type,
      contentImdbId: item.effectiveImdbId,
      contentSeason: season,
      contentEpisode: episode,
      startAtPercent: slotProgress,
      playableSources: playableSources,
      sourceIndex: firstPlayableIndex,
      sourceResolver: _sections.guide.createSourceResolver(
        item,
        season: season,
        episode: episode,
      ),
      nowPlayingGuideData: _sections.guide.guideDataFor(nowPlaying),
      nextUpGuideData: nextPlaying != null
          ? _sections.guide.guideDataFor(nextPlaying)
          : null,
      baseSlotStartMs: basePlaying.slotStart.millisecondsSinceEpoch,
      slotOffset: slotOffset,
    );
  }

  /// Show a bottom sheet with all available sources so the user can pick one manually.
  /// Returns (resolvedUrl, sourceIndex) or null if dismissed.
  Future<StremioTvResolvedSourceChoice?> showManualSourcePicker(
    List<Torrent> sources,
    StremioMeta item, {
    int? season,
    int? episode,
  }) async {
    final resolver = _sections.guide.createSourceResolver(
      item,
      season: season,
      episode: episode,
    );
    return showModalBottomSheet<StremioTvResolvedSourceChoice?>(
      context: _deps.context(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StremioTvManualSourcePickerSheet(
        sources: sources,
        resolver: resolver,
        validateDirectUrl: _sections.streams.isValidStreamUrl,
      ),
    );
  }

  /// Compute the start progress for a channel based on the max start percent setting.
  /// Returns null (beginning), the raw slot progress, or a deterministic random
  /// value within [0, maxStartPercent] per channel.
  double? computeStartProgress(String channelId, double rawProgress) {
    if (_owners.settings.maxStartPercent == 0)
      return null; // always from beginning
    if (_owners.settings.maxStartPercent < 0) return rawProgress; // no limit
    final cap = _owners.settings.maxStartPercent / 100.0;
    if (rawProgress <= cap) return rawProgress; // slot hasn't reached cap yet
    // Deterministic random within [0, cap] based on channel ID
    final hash = channelId.hashCode.abs();
    return (hash % 1000) / 1000.0 * cap;
  }
}
