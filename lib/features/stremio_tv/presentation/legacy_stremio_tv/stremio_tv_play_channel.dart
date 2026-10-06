import 'dart:async';

import 'package:debrify/features/stremio_tv/application/stremio_tv_stream_quality.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_bindings.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_owners.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_sections.dart';
import 'package:debrify/models/play_loader_art.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_channel.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/play_loader_style.dart';
import 'package:debrify/services/premiumize_service.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/services/torbox_service.dart';
import 'package:debrify/services/torrent_service.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/pipeline_loading_overlay.dart';
import 'package:flutter/material.dart';

class StremioTvPlayChannel {
  StremioTvPlayChannel(this._deps);
  final StremioTvDependencies _deps;
  StremioTvOwners get _owners => _deps.owners;
  StremioTvSections get _sections => _deps.sections;

  Future<void> playChannel(StremioTvChannel channel) async {
    final myGeneration = ++_owners.playback.playGeneration;

    // Ensure items are loaded before trying to play
    if (!channel.hasItems) {
      await _sections.library.ensureChannelItemsLoaded(channel);
      if (!_deps.mounted() || _owners.playback.playGeneration != myGeneration)
        return;
    }

    final nowPlaying = _owners.library.service.getNowPlaying(
      channel,
      rotationMinutes: _sections.library.rotationFor(channel),
      salt: _owners.library.mixSalt,
    );
    if (nowPlaying == null) {
      _sections.library.notifyStartupAutoLaunchFailed(
        'No items available for channel',
      );
      if (_deps.mounted()) {
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          const SnackBar(content: Text('No items available for this channel')),
        );
      }
      return;
    }

    final item = nowPlaying.item;
    _owners.playback.currentSlotProgress = _sections.resolve
        .computeStartProgress(channel.id, nowPlaying.progress);

    if (!item.hasValidId) {
      _sections.library.notifyStartupAutoLaunchFailed(
        'Channel item has no valid ID',
      );
      if (_deps.mounted()) {
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          SnackBar(
            content: Text(
              '${item.name} does not have a valid ID for stream search',
            ),
          ),
        );
      }
      return;
    }

    // Cinematic staged loader (matches Home → detail → Play). Shown up front so
    // it also covers the random-episode resolve; the subtitle is omitted since
    // the episode isn't known yet for series.
    if (!_deps.mounted()) return;
    final app = AppThemeScope.of(_deps.context());
    final pInfo = _sections.streams.tvProviderInfo();
    final overlay = PipelineLoadingOverlay.show(
      _deps.context(),
      posterUrl: item.poster ?? item.background,
      title: item.name,
      providerLabel: pInfo.label,
      providerCode: pInfo.code,
      providerColor: pInfo.color,
      hasCacheCheck: pInfo.cacheCheck,
      // The loader is a dark cinematic plate on every theme (black Material,
      // black-at-alpha scrims), so its ink is `onGlass`, never page ink.
      // `inkOnFill` is already contrast-scored against the accent it sits on.
      loaderGround: app.stremioTv.loaderGround,
      loaderAccent: app.stremioTv.loaderAccent,
      loaderAccent2: app.stremioTv.loaderAccent2,
      railFar: app.stremioTv.loaderRailFar,
      // Settings → Appearance → Play Loader: the same look the Home/detail
      // play path uses, so a Debrify TV launch doesn't contradict the choice.
      style:
          PlayLoaderStyleController.cached == PlayLoaderStyleController.classic
          ? PlayLoaderStyle.classic
          : PlayLoaderStyle.marquee,
      art: PlayLoaderArt.fromMeta(item),
      ink: app.onGlass,
      inkOnFill: app.stremioTv.inkOnFill,
      onCancel: () {
        // The overlay dismisses itself; just abort the in-flight play. Every
        // await below bails on the _playGeneration mismatch.
        _owners.playback.playGeneration++;
        _sections.library.notifyStartupAutoLaunchFailed('Playback canceled');
      },
    );

    // For series, resolve a random episode first
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

      if (!_deps.mounted() || _owners.playback.playGeneration != myGeneration) {
        overlay.dismiss();
        return;
      }

      if (resolved == null) {
        overlay.dismiss();
        _sections.library.notifyStartupAutoLaunchFailed(
          'Could not resolve episode',
        );
        if (_deps.mounted()) {
          ScaffoldMessenger.of(_deps.context()).showSnackBar(
            SnackBar(
              content: Text('Could not resolve episode for ${item.name}'),
            ),
          );
        }
        return;
      }

      season = resolved.season;
      episode = resolved.episode;
      _owners.playback.currentPlayTitle = '${item.name} (S${season}E$episode)';
      debugPrint('StremioTV: Playing ${item.name} S${season}E$episode');
    } else {
      _owners.playback.currentPlayTitle = null;
    }

    try {
      final isMovie = item.type.toLowerCase() == 'movie';
      final results = await TorrentService.searchByImdbWithStremio(
        item.effectiveImdbId ?? item.id,
        includeMediaServers: false,
        isMovie: isMovie,
        season: season,
        episode: episode,
        contentType: item.type,
        stremioTimeout: const Duration(seconds: 7),
        engineTimeout: const Duration(seconds: 10),
      );

      if (!_deps.mounted() || _owners.playback.playGeneration != myGeneration) {
        overlay.dismiss();
        return;
      }

      final torrents = results['torrents'] as List<Torrent>? ?? [];
      final directCount = torrents.where((t) => t.isDirectStream).length;
      final torrentCount = torrents
          .where((t) => !t.isDirectStream && !t.isExternalStream)
          .length;
      overlay.setStage(
        PlayLoadStage.searching,
        sourceCount: directCount + torrentCount,
      );

      if (torrents.isEmpty) {
        overlay.dismiss();
        _sections.library.notifyStartupAutoLaunchFailed('No streams found');
        if (_deps.mounted()) {
          ScaffoldMessenger.of(_deps.context()).showSnackBar(
            SnackBar(content: Text('No streams found for ${item.name}')),
          );
        }
        return;
      }

      // Build playable sources list (exclude external URLs and tiny junk files)
      // Direct streams under 5MB are placeholder/tracking files (e.g. mytrakt sync)
      // Filter out 480p torrents — rarely cached on debrid services
      var playableSources = torrents
          .where((t) => !t.isExternalStream)
          .where((t) => !t.isDirectStream || t.sizeBytes >= 5 * 1024 * 1024)
          .where(
            (t) =>
                t.streamType != StreamType.torrent ||
                StremioTvStreamQuality.extractQuality(t.name) != '480p',
          )
          .toList();

      // Drop torrents that belong to a different episode (see
      // _filterTorrentsForEpisode) — keyword engines return the whole series,
      // and the top-seeded wrong episode would otherwise win auto-play.
      if (!isMovie && season != null && episode != null) {
        playableSources = _sections.streams.filterTorrentsForEpisode(
          playableSources,
          season: season,
          episode: episode,
        );
      }

      // For TorBox, filter torrent sources to only cached ones
      if (_owners.settings.debridProvider == 'torbox') {
        final tbKey = await TorboxStorage.getTorboxApiKey();
        if (tbKey != null && tbKey.isNotEmpty) {
          final torrentHashes = playableSources
              .where((t) => t.streamType == StreamType.torrent)
              .map((t) => t.infohash.trim().toLowerCase())
              .where((h) => h.isNotEmpty)
              .toList();
          if (torrentHashes.isNotEmpty) {
            if (!_deps.mounted()) {
              overlay.dismiss();
              return;
            }
            overlay.setStage(PlayLoadStage.cacheCheck);
            final cachedHashes = await TorboxService.checkCachedTorrents(
              apiKey: tbKey,
              infoHashes: torrentHashes,
            );
            final cachedSet = cachedHashes
                .map((h) => h.trim().toLowerCase())
                .toSet();
            overlay.setStage(
              PlayLoadStage.cacheCheck,
              cachedCount: cachedSet.length,
            );
            debugPrint(
              'StremioTV: TorBox cache check: ${cachedSet.length} cached '
              'out of ${torrentHashes.length} torrents',
            );
            // Keep direct streams + only cached torrents
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

      // For Premiumize, filter torrent sources to only cached ones
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
            if (!_deps.mounted()) {
              overlay.dismiss();
              return;
            }
            overlay.setStage(PlayLoadStage.cacheCheck);
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
            overlay.setStage(
              PlayLoadStage.cacheCheck,
              cachedCount: cachedSet.length,
            );
            debugPrint(
              'StremioTV: Premiumize cache check: ${cachedSet.length} cached '
              'out of ${torrentHashes.length} torrents',
            );
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

      if (playableSources.isEmpty) {
        overlay.dismiss();
        _sections.library.notifyStartupAutoLaunchFailed(
          'No playable streams found',
        );
        if (_deps.mounted()) {
          ScaffoldMessenger.of(_deps.context()).showSnackBar(
            SnackBar(
              content: Text('No playable streams found for ${item.name}'),
            ),
          );
        }
        return;
      }

      // Try to find the best stream to auto-play
      if (_owners.settings.preferredQuality != 'auto') {
        debugPrint(
          'StremioTV: Preferred quality: ${_owners.settings.preferredQuality}',
        );
      }

      String? firstPlayableUrl;
      int firstPlayableIndex = 0;

      // Resolving the actual stream URL via the debrid provider.
      overlay.setStage(PlayLoadStage.preparing);

      // Try torrents or direct streams based on setting, fall back to the other
      ({String url, int index})? resolved;
      if (_owners.settings.torrentsFirst) {
        resolved = await _sections.streams.tryTorrentsViaDebrid(
          playableSources,
          item,
          myGeneration,
          season: season,
          episode: episode,
        );
        resolved ??= await _sections.streams.tryDirectStreams(
          playableSources,
          myGeneration,
        );
      } else {
        resolved = await _sections.streams.tryDirectStreams(
          playableSources,
          myGeneration,
        );
        resolved ??= await _sections.streams.tryTorrentsViaDebrid(
          playableSources,
          item,
          myGeneration,
          season: season,
          episode: episode,
        );
      }
      if (resolved != null) {
        firstPlayableUrl = resolved.url;
        firstPlayableIndex = resolved.index;
      }

      if (firstPlayableUrl == null || firstPlayableUrl.isEmpty) {
        overlay.dismiss();
        _sections.library.notifyStartupAutoLaunchFailed(
          'No auto-play stream resolved',
        );
        // Skip the manual picker if the play was cancelled mid-resolve.
        if (_deps.mounted() &&
            _owners.playback.playGeneration == myGeneration) {
          // Show source picker so user can manually select
          final result = await _sections.resolve.showManualSourcePicker(
            playableSources,
            item,
            season: season,
            episode: episode,
          );
          if (result != null && _deps.mounted()) {
            _sections.library.notifyStartupPlayerLaunching();
            _sections.guide.rememberPlaybackCursor(
              channel.id,
              baseSlotStartMs: nowPlaying.slotStart.millisecondsSinceEpoch,
              slotOffset: 0,
            );
            await VideoPlayerLauncher.push(
              _deps.context(),
              VideoPlayerLaunchArgs(
                videoUrl: result.url,
                title: _owners.playback.currentPlayTitle ?? item.name,
                startAtPercent: _owners.playback.currentSlotProgress,
                contentImdbId: item.effectiveImdbId,
                contentTitle: item.name,
                contentType: item.type,
                contentSeason: season,
                contentEpisode: episode,
                stremioSources: playableSources,
                stremioCurrentSourceIndex: result.sourceIndex,
                resolveStremioSource: _sections.guide.createSourceResolver(
                  item,
                  season: season,
                  episode: episode,
                ),
                stremioTvChannels: _sections.guide.buildGuideChannelMetadata(),
                stremioTvCurrentChannelId: channel.id,
                stremioTvRotationMinutes: _owners.settings.rotationMinutes,
                stremioTvSeriesRotationMinutes:
                    _owners.settings.seriesRotationMinutes,
                stremioTvMixSalt: _owners.library.mixSalt,
                stremioTvGuideDataProvider: _sections.guide
                    .createGuideDataProvider(),
                stremioTvChannelSwitchProvider: _sections.guide
                    .createChannelSwitchProvider(),
                stremioTvNextProvider: _sections.guide.createNextProvider(),
              ),
            );
          }
        }
        return;
      }

      // Also honour a Cancel that landed while the stream was resolving — the
      // resolve helpers can return a valid URL after onCancel bumped the
      // generation, and this is the last gate before launch.
      if (!_deps.mounted() || _owners.playback.playGeneration != myGeneration) {
        overlay.dismiss();
        return;
      }

      // Tick the final stage, then dismiss right before the player launches.
      overlay.setStage(PlayLoadStage.starting);
      overlay.dismiss();
      _sections.library.notifyStartupPlayerLaunching();
      _sections.guide.rememberPlaybackCursor(
        channel.id,
        baseSlotStartMs: nowPlaying.slotStart.millisecondsSinceEpoch,
        slotOffset: 0,
      );

      // Launch player with all sources for in-player switching
      await VideoPlayerLauncher.push(
        _deps.context(),
        VideoPlayerLaunchArgs(
          videoUrl: firstPlayableUrl,
          title: _owners.playback.currentPlayTitle ?? item.name,
          startAtPercent: _owners.playback.currentSlotProgress,
          contentImdbId: item.effectiveImdbId,
          contentTitle: item.name,
          contentType: item.type,
          contentSeason: season,
          contentEpisode: episode,
          stremioSources: playableSources,
          stremioCurrentSourceIndex: firstPlayableIndex,
          resolveStremioSource: _sections.guide.createSourceResolver(
            item,
            season: season,
            episode: episode,
          ),
          stremioTvChannels: _sections.guide.buildGuideChannelMetadata(),
          stremioTvCurrentChannelId: channel.id,
          stremioTvRotationMinutes: _owners.settings.rotationMinutes,
          stremioTvSeriesRotationMinutes:
              _owners.settings.seriesRotationMinutes,
          stremioTvMixSalt: _owners.library.mixSalt,
          stremioTvGuideDataProvider: _sections.guide.createGuideDataProvider(),
          stremioTvChannelSwitchProvider: _sections.guide
              .createChannelSwitchProvider(),
          stremioTvNextProvider: _sections.guide.createNextProvider(),
        ),
      );
    } catch (e) {
      overlay.dismiss();
      _sections.library.notifyStartupAutoLaunchFailed(
        'Error searching streams: $e',
      );
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(
        _deps.context(),
      ).showSnackBar(SnackBar(content: Text('Error searching streams: $e')));
    }
  }
}
