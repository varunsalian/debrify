import 'dart:async';
import 'package:collection/collection.dart';
import 'package:debrify/features/stremio_tv/application/stremio_tv_stream_quality.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_bindings.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_owners.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_sections.dart';
import 'package:debrify/models/play_loader_art.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_channel.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/catalog_item_detail_screen.dart';
import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_empty_state.dart';
import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_guide_sheet.dart';
import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_local_catalogs_dialog.dart';
import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_tuner.dart';
import 'package:debrify/services/analytics_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/play_loader_style.dart';
import 'package:debrify/services/premiumize_service.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/stremio_tv_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/services/torbox_service.dart';
import 'package:debrify/services/torrent_service.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/pipeline_loading_overlay.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Main Stremio TV screen — a TV guide powered by Stremio addon catalogs.
///
/// Each addon catalog becomes a "channel" with a deterministic "now playing"
/// item that rotates on a configurable schedule.
class StremioTvScreen extends StatefulWidget {
  /// The resolved native Android-TV flag, threaded down from the app shell
  /// (see main.dart `_buildPage`). Prefer this over a width heuristic: on a TV
  /// the logical canvas sits right at the old `width >= 900` threshold, so
  /// screens that guessed from width flipped to the non-navigable phone layout.
  final bool isTelevision;

  const StremioTvScreen({super.key, this.isTelevision = false});

  @override
  State<StremioTvScreen> createState() => _StremioTvScreenState();
}

class _StremioTvScreenState extends State<StremioTvScreen> {
  final StremioTvOwners _owners = StremioTvOwners();
  StremioTvSections? _composition;
  StremioTvSections get _sections => _composition ??= StremioTvSections(
    StremioTvDependencies(
      owners: _owners,
      context: () => context,
      mounted: () => mounted,
      setState: setState,
      isTelevision: () => widget.isTelevision,
      playChannelById: playChannelById,
    ),
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('stremio_tv');
    _sections.settings.loadSettings().then(
      (_) => _sections.library.discoverAndLoad(),
    );
    MdblistService.instance.isAuthenticated().then((v) {
      if (mounted && v != _owners.settings.mdblistConnected) {
        setState(() => _owners.settings.mdblistConnected = v);
      }
    });

    // Search DPAD exits live on the TvTextField (onUp/Down/Left/RightArrow).
    _owners.focus.searchController.addListener(() {
      final q = _owners.focus.searchController.text.toLowerCase().trim();
      if (q != _owners.focus.searchQuery) {
        setState(() => _owners.focus.searchQuery = q);
      }
    });

    // Register TV sidebar focus handler (tab index 9 = Stremio TV)
    _owners.focus.tvContentFocusHandler = () {
      _owners.focus.searchBtnFocusNode.requestFocus();
    };
    MainPageBridge.registerTvContentFocusHandler(
      9,
      _owners.focus.tvContentFocusHandler!,
    );

    // Register the auto-play bridge
    MainPageBridge.watchStremioTvChannel = (channelId) async {
      if (mounted) {
        _sections.legacy.playChannelById(channelId);
      }
    };

    // Check for pending auto-play
    final pending = MainPageBridge.getAndClearStremioTvChannelToAutoPlay();
    if (pending != null) {
      _owners.playback.pendingChannelId = pending;
    }

    // No periodic screen-level refresh: the tuner runs its own 15s tick
    // (gated on the Auto-refresh setting, passed below) for progress bars
    // and slot rollovers, so a 30s whole-screen setState here was pure
    // rebuild churn on top of it.
  }

  @override
  void dispose() {
    _owners.library.contentRevision.dispose();
    _owners.focus.searchBtnFocusNode.dispose();
    _owners.focus.providerFocusNode.dispose();
    _owners.focus.menuFocusNode.dispose();
    _owners.focus.submenuFocusNode.dispose();
    _owners.focus.searchController.dispose();
    _owners.focus.searchFocusNode.dispose();
    for (final node in _owners.focus.rowFocusNodes) {
      node.dispose();
    }
    // Only clear if we're the active handler
    if (MainPageBridge.watchStremioTvChannel != null) {
      MainPageBridge.watchStremioTvChannel = null;
    }
    if (_owners.focus.tvContentFocusHandler != null) {
      MainPageBridge.unregisterTvContentFocusHandler(
        9,
        _owners.focus.tvContentFocusHandler!,
      );
    }
    super.dispose();
  }

  Future<void> playChannel(StremioTvChannel channel) async {
    final myGeneration = ++_owners.playback.playGeneration;

    // Ensure items are loaded before trying to play
    if (!channel.hasItems) {
      await _sections.library.ensureChannelItemsLoaded(channel);
      if (!mounted || _owners.playback.playGeneration != myGeneration) return;
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
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
    if (!mounted) return;
    final app = AppThemeScope.of(context);
    final pInfo = _sections.streams.tvProviderInfo();
    final overlay = PipelineLoadingOverlay.show(
      context,
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

      if (!mounted || _owners.playback.playGeneration != myGeneration) {
        overlay.dismiss();
        return;
      }

      if (resolved == null) {
        overlay.dismiss();
        _sections.library.notifyStartupAutoLaunchFailed(
          'Could not resolve episode',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
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

      if (!mounted || _owners.playback.playGeneration != myGeneration) {
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
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
            if (!mounted) {
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
            if (!mounted) {
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
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
        if (mounted && _owners.playback.playGeneration == myGeneration) {
          // Show source picker so user can manually select
          final result = await _sections.resolve.showManualSourcePicker(
            playableSources,
            item,
            season: season,
            episode: episode,
          );
          if (result != null && mounted) {
            _sections.library.notifyStartupPlayerLaunching();
            _sections.guide.rememberPlaybackCursor(
              channel.id,
              baseSlotStartMs: nowPlaying.slotStart.millisecondsSinceEpoch,
              slotOffset: 0,
            );
            await VideoPlayerLauncher.push(
              context,
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
      if (!mounted || _owners.playback.playGeneration != myGeneration) {
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
        context,
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
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error searching streams: $e')));
    }
  }

  void playChannelById(String channelId) {
    if (_owners.library.channels.isEmpty) {
      _sections.library.notifyStartupAutoLaunchFailed('Channels not loaded');
      return;
    }
    if (_owners.playback.startupAutoPlayActive &&
        !_owners.library.channels.any((channel) => channel.id == channelId)) {
      _sections.library.notifyStartupAutoLaunchFailed(
        'Startup channel not found',
      );
      return;
    }
    final channel = _owners.library.channels.firstWhere(
      (ch) => ch.id == channelId,
      orElse: () => _owners.library.channels.first,
    );
    playChannel(channel);
  }

  // ============================================================================
  // Channel Detail (cinematic "tune-in")
  // ============================================================================

  /// Tune in: opens the reused [CatalogItemDetailScreen] for the channel's
  /// now-playing item with a fast zoom/fade so selecting a channel feels
  /// like committing to it rather than a stock page push.
  Future<void> openChannelDetail(StremioTvChannel channel) async {
    if (_owners.playback.pushingChannelDetail) return;
    _owners.playback.pushingChannelDetail = true;
    try {
      await _pushChannelDetail(channel);
    } finally {
      _owners.playback.pushingChannelDetail = false;
    }
  }

  Future<void> _pushChannelDetail(StremioTvChannel channel) async {
    if (!channel.hasItems) {
      await _sections.library.ensureChannelItemsLoaded(channel);
      // _ensureChannelItemsLoaded early-returns when a load is already in
      // flight (the Tuner kicks one off on focus), so the await above may
      // not have actually waited. Poll the in-flight load to settle before
      // deciding there's nothing to show — otherwise "View details" on a
      // still-tuning channel wrongly reports "No items available".
      var waitedMs = 0;
      while (mounted &&
          !channel.hasItems &&
          _owners.library.loadingChannelIds.contains(channel.id) &&
          waitedMs < 8000) {
        await Future.delayed(const Duration(milliseconds: 120));
        waitedMs += 120;
      }
      if (!mounted) return;
    }
    final nowPlaying = _owners.library.service.getNowPlaying(
      channel,
      rotationMinutes: _sections.library.rotationFor(channel),
      salt: _owners.library.mixSalt,
    );
    if (nowPlaying == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No items available for this channel')),
        );
      }
      return;
    }
    final screen = CatalogItemDetailScreen(
      item: nowPlaying.item,
      isTelevision: widget.isTelevision,
      onPlay: () => playChannel(channel),
      onBrowse: () => playChannel(channel),
      enablePrimarySourcesHold: false,
    );
    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => screen,
      ),
    );
  }

  // ============================================================================
  // Channel Guide
  // ============================================================================

  Future<void> showGuide(StremioTvChannel channel) async {
    if (!channel.hasItems) {
      await _sections.library.ensureChannelItemsLoaded(channel);
      if (!mounted) return;
    }
    if (channel.items.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No items available for this channel')),
        );
      }
      return;
    }

    final schedule = _owners.library.service.getSchedule(
      channel,
      count: 5,
      rotationMinutes: _sections.library.rotationFor(channel),
      salt: _owners.library.mixSalt,
    );
    if (schedule.isEmpty || !mounted) return;

    final tappedIndex = await StremioTvGuideSheet.show(
      context,
      channel: channel,
      schedule: schedule,
    );

    if (tappedIndex != null && mounted) {
      playChannel(channel);
    }
  }

  // ============================================================================
  // Favorites
  // ============================================================================

  Future<void> toggleFavorite(StremioTvChannel channel) async {
    final focusedChannelId = _sections.navigation.currentFocusedChannelId();
    final newState = !channel.isFavorite;
    await StremioTvStorage.setStremioTvChannelFavorited(channel.id, newState);
    if (!mounted) return;
    final previousChannels = List<StremioTvChannel>.from(
      _owners.library.channels,
    );
    setState(() {
      channel.isFavorite = newState;
      _owners.library.channels = _sections.library.sortedChannels(
        _owners.library.channels,
      );
      _sections.navigation.reorderRowFocusNodes(
        previousChannels,
        _owners.library.channels,
      );
    });
    if (focusedChannelId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final newIndex = _owners.library.channels.indexWhere(
          (ch) => ch.id == focusedChannelId,
        );
        if (newIndex >= 0 && newIndex < _owners.focus.rowFocusNodes.length) {
          _owners.focus.rowFocusNodes[newIndex].requestFocus();
        }
      });
    }
  }

  Future<void> copyLocalCatalogJson(StremioTvChannel channel) async {
    final payload = await LocalCatalogExporter.loadCatalog(
      catalogId: channel.catalog.id,
      catalogType: channel.type,
    );
    if (!mounted) return;
    if (payload == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Local catalog could not be found'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: payload.json));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied "${payload.name}" JSON to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> editLocalCatalog(StremioTvChannel channel) async {
    final previousFocusedIndex = _owners.focus.focusedIndex;
    final previousFocusedChannelId = _sections.navigation
        .currentFocusedChannelId();
    final previousFilteredIndex = previousFocusedChannelId == null
        ? -1
        : _sections.navigation.filteredChannels.indexWhere(
            (ch) => ch.id == previousFocusedChannelId,
          );
    final changed = await StremioTvLocalCatalogEditorDialog.show(
      context,
      catalogId: channel.catalog.id,
      catalogType: channel.type,
    );
    if (changed != true || !mounted) return;

    await _sections.library.refresh();
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      void focusChannelById(String channelId) {
        final channelIndex = _owners.library.channels.indexWhere(
          (ch) => ch.id == channelId,
        );
        if (channelIndex >= 0 &&
            channelIndex < _owners.focus.rowFocusNodes.length) {
          _owners.focus.rowFocusNodes[channelIndex].requestFocus();
          setState(() => _owners.focus.focusedIndex = channelIndex);
        }
      }

      final visibleChannels = _sections.navigation.filteredChannels;
      final visibleEditedChannel = visibleChannels.firstWhereOrNull(
        (ch) => ch.id == channel.id,
      );
      if (visibleEditedChannel != null) {
        focusChannelById(visibleEditedChannel.id);
        return;
      }

      final visiblePreviousChannel = previousFocusedChannelId == null
          ? null
          : visibleChannels.firstWhereOrNull(
              (ch) => ch.id == previousFocusedChannelId,
            );
      if (visiblePreviousChannel != null) {
        focusChannelById(visiblePreviousChannel.id);
        return;
      }

      if (visibleChannels.isNotEmpty) {
        final fallbackVisibleIndex = previousFilteredIndex >= 0
            ? previousFilteredIndex.clamp(0, visibleChannels.length - 1)
            : previousFocusedIndex.clamp(0, visibleChannels.length - 1);
        focusChannelById(visibleChannels[fallbackVisibleIndex].id);
        return;
      }

      _owners.focus.searchBtnFocusNode.requestFocus();
    });
  }

  // ============================================================================
  // Build
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = AppThemeScope.of(context);

    return Scaffold(
      // Match the Home board: sit the whole screen on the same cinematic
      // indigo→near-black wash instead of a flat black, so the tuner reads as
      // part of the same app rather than a separate dark surface.
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: app.home.wash),
        child: _owners.library.loading
            ? _sections.chrome.buildLoadingSkeleton()
            : Column(
                children: [
                  // Premium header bar
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          app.home.bg,
                          app.home.bg.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Collapsible search field
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          alignment: Alignment.topCenter,
                          child: _owners.focus.showSearchField
                              ? Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Focus(
                                    canRequestFocus: false,
                                    skipTraversal: true,
                                    onKeyEvent: _sections
                                        .navigation
                                        .handleSearchBarBack,
                                    child: TvTextField(
                                      controller:
                                          _owners.focus.searchController,
                                      focusNode: _owners.focus.searchFocusNode,
                                      style: TextStyle(color: app.core.tx),
                                      accent: app.youtube.focus,
                                      keyboardGround: app.youtube.keyboardPanel,
                                      keyboardInk: app.core.tx,
                                      keyboardInkOnAccent: app.inkOn(
                                        app.youtube.focus,
                                      ),
                                      onSubmitted: (_) => _owners
                                          .focus
                                          .searchBtnFocusNode
                                          .requestFocus(),
                                      onDownArrow: () => _owners
                                          .focus
                                          .searchBtnFocusNode
                                          .requestFocus(),
                                      onUpArrow: () {
                                        // Search bar is at the top — nothing above
                                      },
                                      onLeftArrow: () =>
                                          MainPageBridge.focusTvSidebar?.call(),
                                      onRightArrow: () {
                                        // Nothing to the right — consume
                                      },
                                      decoration: InputDecoration(
                                        hintText: 'Search channels...',
                                        hintStyle: TextStyle(
                                          color: app.core.tx.withValues(
                                            alpha: 0.3,
                                          ),
                                        ),
                                        prefixIcon: Icon(
                                          Icons.search_rounded,
                                          color: app.core.tx.withValues(
                                            alpha: 0.35,
                                          ),
                                        ),
                                        suffixIcon:
                                            _owners.focus.searchQuery.isNotEmpty
                                            ? IconButton(
                                                icon: Icon(
                                                  Icons.close_rounded,
                                                  color: app.core.tx.withValues(
                                                    alpha: 0.5,
                                                  ),
                                                ),
                                                onPressed: () {
                                                  _owners.focus.searchController
                                                      .clear();
                                                  setState(() {
                                                    _owners
                                                            .focus
                                                            .showSearchField =
                                                        false;
                                                  });
                                                },
                                              )
                                            : null,
                                        border: OutlineInputBorder(
                                          borderRadius: app.shape.br(14),
                                          borderSide: BorderSide.none,
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: app.shape.br(14),
                                          borderSide: BorderSide.none,
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: app.shape.br(14),
                                          borderSide: BorderSide(
                                            color: app.core.tx.withValues(
                                              alpha: 0.15,
                                            ),
                                            width: 1,
                                          ),
                                        ),
                                        filled: true,
                                        fillColor: app.core.tx.withValues(
                                          alpha: 0.07,
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 14,
                                            ),
                                      ),
                                      textInputAction: TextInputAction.search,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Search toggle button
                            Focus(
                              focusNode: _owners.focus.searchBtnFocusNode,
                              onKeyEvent: (node, event) {
                                if (event is! KeyDownEvent) {
                                  return KeyEventResult.ignored;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowRight) {
                                  _owners.focus.menuFocusNode.requestFocus();
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowLeft) {
                                  MainPageBridge.focusTvSidebar?.call();
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowUp) {
                                  if (_owners.focus.showSearchField) {
                                    _owners.focus.searchFocusNode
                                        .requestFocus();
                                  }
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowDown) {
                                  _sections.navigation.focusDialFromHeader();
                                  return KeyEventResult.handled;
                                }
                                if (isActivateKey(event.logicalKey)) {
                                  setState(() {
                                    _owners.focus.showSearchField =
                                        !_owners.focus.showSearchField;
                                  });
                                  if (_owners.focus.showSearchField) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          _owners.focus.searchFocusNode
                                              .requestFocus();
                                        });
                                  }
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              },
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _owners.focus.showSearchField =
                                        !_owners.focus.showSearchField;
                                  });
                                  if (_owners.focus.showSearchField) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          _owners.focus.searchFocusNode
                                              .requestFocus();
                                        });
                                  }
                                },
                                child: ListenableBuilder(
                                  listenable: _owners.focus.searchBtnFocusNode,
                                  builder: (context, _) =>
                                      _sections.chrome.headerButton(
                                        focused: _owners
                                            .focus
                                            .searchBtnFocusNode
                                            .hasFocus,
                                        active:
                                            _owners.focus.showSearchField ||
                                            _owners
                                                .focus
                                                .searchQuery
                                                .isNotEmpty,
                                        child: Icon(
                                          Icons.search_rounded,
                                          size: 20,
                                          color:
                                              (_owners
                                                      .focus
                                                      .searchBtnFocusNode
                                                      .hasFocus ||
                                                  _owners
                                                      .focus
                                                      .showSearchField ||
                                                  _owners
                                                      .focus
                                                      .searchQuery
                                                      .isNotEmpty)
                                              ? app.core.tx
                                              : app.core.tx.withValues(
                                                  alpha: 0.5,
                                                ),
                                        ),
                                      ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Options button
                            Focus(
                              focusNode: _owners.focus.menuFocusNode,
                              onKeyEvent: (node, event) {
                                if (event is! KeyDownEvent) {
                                  return KeyEventResult.ignored;
                                }
                                if (_owners.focus.menuController.isOpen) {
                                  if (event.logicalKey ==
                                          LogicalKeyboardKey.escape ||
                                      event.logicalKey ==
                                          LogicalKeyboardKey.goBack) {
                                    _owners.focus.menuController.close();
                                    _owners.focus.menuFocusNode.requestFocus();
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowUp) {
                                  if (_owners.focus.showSearchField) {
                                    _owners.focus.searchFocusNode
                                        .requestFocus();
                                  }
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowRight) {
                                  if (_owners
                                      .settings
                                      .availableProviders
                                      .isNotEmpty) {
                                    _owners.focus.providerFocusNode
                                        .requestFocus();
                                  }
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowLeft) {
                                  _owners.focus.searchBtnFocusNode
                                      .requestFocus();
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowDown) {
                                  _sections.navigation.focusDialFromHeader();
                                  return KeyEventResult.handled;
                                }
                                if (isActivateKey(event.logicalKey)) {
                                  _owners.focus.menuController.open();
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              },
                              child: ListenableBuilder(
                                listenable: _owners.focus.menuFocusNode,
                                builder: (context, child) => MenuAnchor(
                                  controller: _owners.focus.menuController,
                                  menuChildren: [
                                    _sections.chrome.topMenuItem(
                                      autofocus: true,
                                      leadingIcon: const Icon(
                                        Icons.shuffle_rounded,
                                      ),
                                      controller: _owners.focus.menuController,
                                      anchorFocusNode:
                                          _owners.focus.menuFocusNode,
                                      closeOnArrowUp: true,
                                      onPressed: () {
                                        setState(
                                          () => _owners.library.mixSalt =
                                              (_owners.library.mixSalt + 1) %
                                              10,
                                        );
                                      },
                                      label:
                                          'Shuffle (Mix ${_owners.library.mixSalt + 1})',
                                    ),
                                    MenuItemButton(
                                      leadingIcon: const Icon(
                                        Icons.refresh_rounded,
                                      ),
                                      onPressed: _owners.library.refreshing
                                          ? null
                                          : () => _sections.library.refresh(),
                                      child: const Text('Refresh'),
                                    ),
                                    MenuItemButton(
                                      leadingIcon: const Icon(
                                        Icons.tune_rounded,
                                      ),
                                      onPressed: () => _sections.menuActions
                                          .openChannelFilter(),
                                      child: const Text('Filter channels'),
                                    ),
                                    MenuItemButton(
                                      leadingIcon: const Icon(
                                        Icons.settings_rounded,
                                      ),
                                      onPressed: _sections
                                          .settings
                                          .openStremioTvSettings,
                                      child: const Text('Stremio TV Settings'),
                                    ),
                                    SubmenuButton(
                                      focusNode: _owners.focus.submenuFocusNode,
                                      leadingIcon: const Icon(
                                        Icons.playlist_add_rounded,
                                      ),
                                      menuChildren: [
                                        _sections.chrome.submenuItem(
                                          autofocus: true,
                                          icon: Icons.list_rounded,
                                          label: 'Manage',
                                          onPressed: _sections
                                              .menuActions
                                              .openLocalCatalogs,
                                        ),
                                        _sections.chrome.submenuItem(
                                          icon: Icons.file_upload_outlined,
                                          label: 'From File',
                                          onPressed: _sections
                                              .menuActions
                                              .importFromFile,
                                        ),
                                        _sections.chrome.submenuItem(
                                          icon: Icons.link_rounded,
                                          label: 'From URL',
                                          onPressed: _sections
                                              .menuActions
                                              .importFromUrl,
                                        ),
                                        _sections.chrome.submenuItem(
                                          icon: Icons.data_object_rounded,
                                          label: 'Paste JSON',
                                          onPressed: _sections
                                              .menuActions
                                              .importFromJson,
                                        ),
                                        _sections.chrome.submenuItem(
                                          icon: Icons.source_rounded,
                                          label: 'From Repository',
                                          onPressed: _sections
                                              .menuActions
                                              .importFromRepo,
                                        ),
                                        _sections.chrome.submenuItem(
                                          icon: Icons.movie_filter_rounded,
                                          label: 'From Trakt',
                                          onPressed: _sections
                                              .menuActions
                                              .importFromTrakt,
                                        ),
                                        // Hidden for the alpha (kMdblistEnabled)
                                        // and only when connected — no dead import.
                                        if (kMdblistEnabled &&
                                            _owners.settings.mdblistConnected)
                                          _sections.chrome.submenuItem(
                                            icon: Icons
                                                .playlist_add_check_circle_outlined,
                                            label: 'From MDBList',
                                            onPressed: _sections
                                                .menuActions
                                                .importFromMdblist,
                                          ),
                                      ],
                                      child: const Text('Import'),
                                    ),
                                  ],
                                  builder: (context, controller, child) =>
                                      _sections.chrome.headerButton(
                                        focused: _owners
                                            .focus
                                            .menuFocusNode
                                            .hasFocus,
                                        child: Icon(
                                          Icons.more_vert_rounded,
                                          size: 20,
                                          color:
                                              _owners
                                                  .focus
                                                  .menuFocusNode
                                                  .hasFocus
                                              ? app.core.tx
                                              : app.core.tx.withValues(
                                                  alpha: 0.5,
                                                ),
                                        ),
                                        onTap: () {
                                          if (controller.isOpen) {
                                            controller.close();
                                          } else {
                                            controller.open();
                                          }
                                        },
                                      ),
                                ),
                              ),
                            ),
                            if (_owners
                                .settings
                                .availableProviders
                                .isNotEmpty) ...[
                              const SizedBox(width: 10),
                              // Provider selector
                              Focus(
                                focusNode: _owners.focus.providerFocusNode,
                                onKeyEvent: (node, event) {
                                  if (event is! KeyDownEvent) {
                                    return KeyEventResult.ignored;
                                  }
                                  if (_owners
                                      .focus
                                      .providerMenuController
                                      .isOpen) {
                                    if (event.logicalKey ==
                                            LogicalKeyboardKey.escape ||
                                        event.logicalKey ==
                                            LogicalKeyboardKey.goBack) {
                                      _owners.focus.providerMenuController
                                          .close();
                                      _owners.focus.providerFocusNode
                                          .requestFocus();
                                      return KeyEventResult.handled;
                                    }
                                    return KeyEventResult.ignored;
                                  }
                                  if (event.logicalKey ==
                                      LogicalKeyboardKey.arrowUp) {
                                    if (_owners.focus.showSearchField) {
                                      _owners.focus.searchFocusNode
                                          .requestFocus();
                                    }
                                    return KeyEventResult.handled;
                                  }
                                  if (event.logicalKey ==
                                      LogicalKeyboardKey.arrowLeft) {
                                    _owners.focus.menuFocusNode.requestFocus();
                                    return KeyEventResult.handled;
                                  }
                                  if (event.logicalKey ==
                                      LogicalKeyboardKey.arrowRight) {
                                    return KeyEventResult.handled;
                                  }
                                  if (event.logicalKey ==
                                      LogicalKeyboardKey.arrowDown) {
                                    _sections.navigation.focusDialFromHeader();
                                    return KeyEventResult.handled;
                                  }
                                  if (isActivateKey(event.logicalKey)) {
                                    _owners.focus.providerMenuController.open();
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                },
                                child: ListenableBuilder(
                                  listenable: _owners.focus.providerFocusNode,
                                  builder: (context, child) => MenuAnchor(
                                    controller:
                                        _owners.focus.providerMenuController,
                                    menuChildren: [
                                      _sections.chrome.topMenuItem(
                                        autofocus: true,
                                        leadingIcon: Icon(
                                          _owners.settings.debridProvider ==
                                                  'auto'
                                              ? Icons.check_rounded
                                              : Icons.circle_outlined,
                                        ),
                                        label: _sections.settings
                                            .providerFullLabel('auto'),
                                        onPressed: () => _sections.settings
                                            .setDebridProvider('auto'),
                                        controller: _owners
                                            .focus
                                            .providerMenuController,
                                        anchorFocusNode:
                                            _owners.focus.providerFocusNode,
                                        closeOnArrowUp: true,
                                      ),
                                      ..._owners.settings.availableProviders
                                          .map(
                                            (provider) => MenuItemButton(
                                              leadingIcon: Icon(
                                                _owners
                                                            .settings
                                                            .debridProvider ==
                                                        provider.key
                                                    ? Icons.check_rounded
                                                    : Icons.circle_outlined,
                                              ),
                                              onPressed: () => _sections
                                                  .settings
                                                  .setDebridProvider(
                                                    provider.key,
                                                  ),
                                              child: Text(provider.value),
                                            ),
                                          ),
                                    ],
                                    builder: (context, controller, child) =>
                                        GestureDetector(
                                          onTap: () {
                                            if (controller.isOpen) {
                                              controller.close();
                                            } else {
                                              controller.open();
                                            }
                                          },
                                          child: _sections.chrome.headerButton(
                                            focused: _owners
                                                .focus
                                                .providerFocusNode
                                                .hasFocus,
                                            wide: true,
                                            child: Text(
                                              _sections.settings
                                                  .providerShortLabel(
                                                    _owners
                                                        .settings
                                                        .debridProvider,
                                                  ),
                                              style: TextStyle(
                                                color:
                                                    _owners
                                                        .focus
                                                        .providerFocusNode
                                                        .hasFocus
                                                    ? app.core.tx
                                                    : app.core.tx.withValues(
                                                        alpha: 0.68,
                                                      ),
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Channel list
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        if (_owners.library.channels.isEmpty) {
                          return const StremioTvEmptyState();
                        }
                        return ValueListenableBuilder<int>(
                          valueListenable: _owners.library.contentRevision,
                          builder: (context, _, __) {
                            // Computed inside the builder so a revision bump
                            // hands the tuner a fresh snapshot consistent with
                            // the live _channels/_rowFocusNodes it also gets.
                            final filtered =
                                _sections.navigation.filteredChannels;
                            if (filtered.isEmpty &&
                                _owners.focus.searchQuery.isNotEmpty) {
                              return Center(
                                child: Text(
                                  'No channels match "${_owners.focus.searchQuery}"',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              );
                            }
                            return StremioTvTuner(
                              controller: _owners.focus.tunerController,
                              channels: filtered,
                              allChannels: _owners.library.channels,
                              rowFocusNodes: _owners.focus.rowFocusNodes,
                              service: _owners.library.service,
                              rotationFor: _sections.library.rotationFor,
                              mixSalt: _owners.library.mixSalt,
                              hideNowPlaying: _owners.settings.hideNowPlaying,
                              autoRefresh: _owners.settings.autoRefresh,
                              isTelevision: widget.isTelevision,
                              loadingChannelIds:
                                  _owners.library.loadingChannelIds,
                              ensureLoaded: (channel) {
                                if (!channel.hasItems &&
                                    !_owners.library.loadingChannelIds.contains(
                                      channel.id,
                                    )) {
                                  _sections.library.ensureChannelItemsLoaded(
                                    channel,
                                  );
                                }
                              },
                              onOpenDetail: openChannelDetail,
                              onPlay: playChannel,
                              // Restore the "max start %" cap on the *displayed*
                              // progress so the bar matches where playback will
                              // actually join (matches the old row's
                              // displayProgress semantics exactly).
                              displayProgress: (channel, rawProgress) {
                                if (_owners.settings.maxStartPercent == 0)
                                  return 0.0;
                                return _sections.resolve.computeStartProgress(
                                      channel.id,
                                      rawProgress,
                                    ) ??
                                    rawProgress;
                              },
                              onToggleFavorite: toggleFavorite,
                              onShowGuide: showGuide,
                              onEditLocal: editLocalCatalog,
                              onExportLocal: copyLocalCatalogJson,
                              onFocusSidebar: () =>
                                  MainPageBridge.focusTvSidebar?.call(),
                              onFocusHeader: () => _owners
                                  .focus
                                  .searchBtnFocusNode
                                  .requestFocus(),
                              onFocusedIndexChanged: (realIndex) {
                                // Bookkeeping only — never read in build(), so
                                // no setState (keeps surfing lag-free) and it
                                // stays current for header↕ navigation even
                                // mid-surf.
                                _owners.focus.focusedIndex = realIndex;
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
