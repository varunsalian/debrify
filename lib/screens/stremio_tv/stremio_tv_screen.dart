import 'dart:async';
import 'package:collection/collection.dart';
import 'package:debrify/features/stremio_tv/application/stremio_tv_stream_quality.dart';
import 'package:debrify/features/stremio_tv/models/stremio_tv_playback_records.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_bindings.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_owners.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_sections.dart';
import 'package:debrify/features/stremio_tv/presentation/stremio_tv_manual_source_picker.dart';
import 'package:debrify/models/play_loader_art.dart';
import 'package:debrify/models/premiumize_file.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_channel.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_now_playing.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/catalog_item_detail_screen.dart';
import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_empty_state.dart';
import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_guide_sheet.dart';
import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_local_catalogs_dialog.dart';
import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_tuner.dart';
import 'package:debrify/services/alldebrid_service.dart';
import 'package:debrify/services/analytics_service.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/pikpak_api_service.dart';
import 'package:debrify/services/pikpak_tv_service.dart';
import 'package:debrify/services/play_loader_style.dart';
import 'package:debrify/services/premiumize_service.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/pikpak_storage.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/stremio_tv_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/services/stream_url_validator.dart';
import 'package:debrify/services/torbox_service.dart';
import 'package:debrify/services/torbox_torrent_control_service.dart';
import 'package:debrify/services/torrent_service.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/rd_blocked_filter.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:debrify/utils/stremio_episode_selector.dart';
import 'package:debrify/utils/stremio_tv_debrid_fallback.dart';
import 'package:debrify/utils/torrent_coverage_detector.dart';
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

  // ============================================================================
  // Playback
  // ============================================================================

  /// Sort streams so those matching [_preferredQuality] come first.
  /// Within same-quality group, preserves original order.
  Future<({String url, int index})?> tryDirectStreams(
    List<Torrent> playableSources,
    int myGeneration,
  ) async {
    final directStreams = _sortStreamsByQuality(
      playableSources.where((t) => t.isDirectStream).toList(),
    );
    final maxDirectAttempts = directStreams.length.clamp(0, 20);
    for (int d = 0; d < maxDirectAttempts; d++) {
      final stream = directStreams[d];
      if (stream.directUrl == null || stream.directUrl!.isEmpty) continue;
      if (!mounted || _owners.playback.playGeneration != myGeneration)
        return null;
      final valid = await isValidStreamUrl(stream.directUrl!);
      if (!mounted || _owners.playback.playGeneration != myGeneration)
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
    final torrentStreams = _sortStreamsByQuality(
      playableSources.where((t) => t.streamType == StreamType.torrent).toList(),
    );
    final maxTorrentAttempts = torrentStreams.length.clamp(0, 20);
    final attemptedTorrents = torrentStreams.take(maxTorrentAttempts).toList();
    final loadAutoTorboxCachedHashes =
        StremioTvDebridFallback.memoizeAsync<Set<String>>(
          () => loadTorboxCachedHashes(
            attemptedTorrents,
            isCancelled: () =>
                !mounted || _owners.playback.playGeneration != myGeneration,
          ),
        );

    for (int i = 0; i < maxTorrentAttempts; i++) {
      if (!mounted || _owners.playback.playGeneration != myGeneration)
        return null;
      final url = await resolveTorrentUrl(
        torrentStreams[i],
        item,
        _owners.settings.debridProvider,
        season: season,
        episode: episode,
        isCancelled: () =>
            !mounted || _owners.playback.playGeneration != myGeneration,
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
    _owners.playback.currentSlotProgress = computeStartProgress(
      channel.id,
      nowPlaying.progress,
    );

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
    final pInfo = tvProviderInfo();
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
        playableSources = filterTorrentsForEpisode(
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
        resolved = await tryTorrentsViaDebrid(
          playableSources,
          item,
          myGeneration,
          season: season,
          episode: episode,
        );
        resolved ??= await tryDirectStreams(playableSources, myGeneration);
      } else {
        resolved = await tryDirectStreams(playableSources, myGeneration);
        resolved ??= await tryTorrentsViaDebrid(
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
          final result = await showManualSourcePicker(
            playableSources,
            item,
            season: season,
            episode: episode,
          );
          if (result != null && mounted) {
            _sections.library.notifyStartupPlayerLaunching();
            rememberPlaybackCursor(
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
                resolveStremioSource: createSourceResolver(
                  item,
                  season: season,
                  episode: episode,
                ),
                stremioTvChannels: buildGuideChannelMetadata(),
                stremioTvCurrentChannelId: channel.id,
                stremioTvRotationMinutes: _owners.settings.rotationMinutes,
                stremioTvSeriesRotationMinutes:
                    _owners.settings.seriesRotationMinutes,
                stremioTvMixSalt: _owners.library.mixSalt,
                stremioTvGuideDataProvider: createGuideDataProvider(),
                stremioTvChannelSwitchProvider: createChannelSwitchProvider(),
                stremioTvNextProvider: createNextProvider(),
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
      rememberPlaybackCursor(
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
          resolveStremioSource: createSourceResolver(
            item,
            season: season,
            episode: episode,
          ),
          stremioTvChannels: buildGuideChannelMetadata(),
          stremioTvCurrentChannelId: channel.id,
          stremioTvRotationMinutes: _owners.settings.rotationMinutes,
          stremioTvSeriesRotationMinutes:
              _owners.settings.seriesRotationMinutes,
          stremioTvMixSalt: _owners.library.mixSalt,
          stremioTvGuideDataProvider: createGuideDataProvider(),
          stremioTvChannelSwitchProvider: createChannelSwitchProvider(),
          stremioTvNextProvider: createNextProvider(),
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
    final slotProgress = computeStartProgress(channel.id, nowPlaying.progress);

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
      playableSources = filterTorrentsForEpisode(
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
      resolved = await tryTorrentsViaDebrid(
        playableSources,
        item,
        gen,
        season: season,
        episode: episode,
      );
      resolved ??= await tryDirectStreams(playableSources, gen);
    } else {
      resolved = await tryDirectStreams(playableSources, gen);
      resolved ??= await tryTorrentsViaDebrid(
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
      sourceResolver: createSourceResolver(
        item,
        season: season,
        episode: episode,
      ),
      nowPlayingGuideData: guideDataFor(nowPlaying),
      nextUpGuideData: nextPlaying != null ? guideDataFor(nextPlaying) : null,
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
    final resolver = createSourceResolver(
      item,
      season: season,
      episode: episode,
    );
    return showModalBottomSheet<StremioTvResolvedSourceChoice?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StremioTvManualSourcePickerSheet(
        sources: sources,
        resolver: resolver,
        validateDirectUrl: isValidStreamUrl,
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

  void rememberPlaybackCursor(
    String channelId, {
    required int baseSlotStartMs,
    required int slotOffset,
  }) {
    _owners.playback.playbackCursors[channelId] = StremioTvPlaybackCursor(
      baseSlotStartMs: baseSlotStartMs,
      slotOffset: slotOffset,
    );
  }

  int _nextSlotOffsetFor(StremioTvChannel channel) {
    final current = _owners.library.service.getNowPlaying(
      channel,
      rotationMinutes: _sections.library.rotationFor(channel),
      salt: _owners.library.mixSalt,
    );
    if (current == null) return 1;

    final currentBaseMs = current.slotStart.millisecondsSinceEpoch;
    final cursor = _owners.playback.playbackCursors[channel.id];
    if (cursor == null || cursor.baseSlotStartMs != currentBaseMs) {
      return 1;
    }
    return cursor.slotOffset + 1;
  }

  Map<String, dynamic> guideDataFor(StremioTvNowPlaying playing) {
    return {
      'title': playing.item.name,
      'poster': playing.item.poster,
      'year': playing.item.year,
      'rating': playing.item.imdbRating,
      'type': playing.item.type,
      'slotEndMs': playing.slotEnd.millisecondsSinceEpoch,
      'progress': playing.progress,
    };
  }

  Map<String, dynamic> _playbackResultToMap(
    String channelId,
    StremioTvChannelPlaybackResult result,
  ) {
    return {
      'channelId': channelId,
      'url': result.url,
      'title': result.title,
      'contentType': result.contentType,
      'contentImdbId': result.contentImdbId,
      if (result.contentSeason != null) 'contentSeason': result.contentSeason,
      if (result.contentEpisode != null)
        'contentEpisode': result.contentEpisode,
      'startAtPercent': result.startAtPercent,
      'stremioSources': result.playableSources.map((t) => t.toJson()).toList(),
      'stremioCurrentSourceIndex': result.sourceIndex,
      'sourceResolver': result.sourceResolver,
      'nowPlaying': result.nowPlayingGuideData,
      if (result.nextUpGuideData != null) 'nextUp': result.nextUpGuideData,
    };
  }

  // ─── Source Resolution (no dialogs, returns URL) ────────────────────

  /// Creates a resolver closure that snapshots current state at creation time.
  Future<String?> Function(Torrent) createSourceResolver(
    StremioMeta item, {
    int? season,
    int? episode,
  }) {
    final debridProvider = _owners.settings.debridProvider;
    return (Torrent torrent) async {
      if (torrent.isDirectStream) {
        return torrent.directUrl;
      }
      if (torrent.streamType == StreamType.torrent) {
        return resolveTorrentUrl(
          torrent,
          item,
          debridProvider,
          season: season,
          episode: episode,
        );
      }
      return null;
    };
  }

  // ─── Stremio TV In-Player Guide ─────────────────────────────────────

  /// Build channel metadata list for the in-player guide.
  /// Includes inline now/next data for channels that already have items loaded.
  List<Map<String, dynamic>> buildGuideChannelMetadata() {
    return _owners.library.channels.map((ch) {
      final data = <String, dynamic>{
        'id': ch.id,
        'name': ch.displayName,
        'number': ch.channelNumber,
        'type': ch.type,
        'isFavorite': ch.isFavorite,
      };
      if (ch.hasItems) {
        final rotation = _sections.library.rotationFor(ch);
        final np = _owners.library.service.getNowPlaying(
          ch,
          rotationMinutes: rotation,
          salt: _owners.library.mixSalt,
        );
        final next = _owners.library.service.getNextPlaying(
          ch,
          rotationMinutes: rotation,
          salt: _owners.library.mixSalt,
        );
        if (np != null) {
          data['nowPlaying'] = {
            'title': np.item.name,
            'poster': np.item.poster,
            'year': np.item.year,
            'rating': np.item.imdbRating,
            'type': np.item.type,
            'slotEndMs': np.slotEnd.millisecondsSinceEpoch,
            'progress': np.progress,
          };
        }
        if (next != null) {
          data['nextUp'] = {
            'title': next.item.name,
            'poster': next.item.poster,
            'year': next.item.year,
            'rating': next.item.imdbRating,
            'type': next.item.type,
          };
        }
      }
      return data;
    }).toList();
  }

  /// Creates a guide data provider closure for lazy-loading channel data.
  Future<Map<String, dynamic>?> Function(List<String>)
  createGuideDataProvider() {
    return (List<String> channelIds) async {
      final result = <String, dynamic>{};
      for (final id in channelIds) {
        final ch = _owners.library.channels.firstWhereOrNull((c) => c.id == id);
        if (ch == null) continue;
        if (!ch.hasItems) await _owners.library.service.loadChannelItems(ch);
        if (!ch.hasItems) continue;
        final rotation = _sections.library.rotationFor(ch);
        final np = _owners.library.service.getNowPlaying(
          ch,
          rotationMinutes: rotation,
          salt: _owners.library.mixSalt,
        );
        final next = _owners.library.service.getNextPlaying(
          ch,
          rotationMinutes: rotation,
          salt: _owners.library.mixSalt,
        );
        result[id] = {
          if (np != null)
            'nowPlaying': {
              'title': np.item.name,
              'poster': np.item.poster,
              'year': np.item.year,
              'rating': np.item.imdbRating,
              'type': np.item.type,
              'slotEndMs': np.slotEnd.millisecondsSinceEpoch,
              'progress': np.progress,
            },
          if (next != null)
            'nextUp': {
              'title': next.item.name,
              'poster': next.item.poster,
              'year': next.item.year,
              'rating': next.item.imdbRating,
              'type': next.item.type,
            },
        };
      }
      return result;
    };
  }

  /// Creates a channel switch provider closure for the in-player guide.
  Future<Map<String, dynamic>?> Function(String) createChannelSwitchProvider() {
    return (String channelId) async {
      final ch = _owners.library.channels.firstWhereOrNull(
        (c) => c.id == channelId,
      );
      if (ch == null) return null;
      final result = await resolveChannelPlayback(ch);
      if (result == null) return null;
      rememberPlaybackCursor(
        channelId,
        baseSlotStartMs: result.baseSlotStartMs,
        slotOffset: result.slotOffset,
      );
      return _playbackResultToMap(channelId, result);
    };
  }

  /// Creates a provider for the player Next button in Stremio TV mode.
  ///
  /// It advances one guide slot at a time and keeps a small per-channel cursor.
  /// An unavailable slot is reported to the player instead of silently skipping
  /// over another series and making the channel appear to contain one title.
  /// The failed slot is still remembered, so another explicit Next press moves
  /// on rather than retrying it forever.
  Future<Map<String, dynamic>?> Function(String) createNextProvider() {
    return (String channelId) async {
      final ch = _owners.library.channels.firstWhereOrNull(
        (c) => c.id == channelId,
      );
      if (ch == null) return null;

      final slotOffset = _nextSlotOffsetFor(ch);
      final result = await resolveChannelPlayback(ch, slotOffset: slotOffset);
      if (result != null) {
        rememberPlaybackCursor(
          channelId,
          baseSlotStartMs: result.baseSlotStartMs,
          slotOffset: result.slotOffset,
        );
        return _playbackResultToMap(channelId, result);
      }

      debugPrint(
        'StremioTV next: slot offset $slotOffset unavailable; '
        'not skipping it silently.',
      );
      final current = _owners.library.service.getNowPlaying(
        ch,
        rotationMinutes: _sections.library.rotationFor(ch),
        salt: _owners.library.mixSalt,
      );
      if (current != null) {
        rememberPlaybackCursor(
          channelId,
          baseSlotStartMs: current.slotStart.millisecondsSinceEpoch,
          slotOffset: slotOffset,
        );
      }
      return null;
    };
  }

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
              : await loadTorboxCachedHashes(<Torrent>[
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
          return _resolveViaRealDebrid(
            torrent,
            item,
            apiKey,
            season: season,
            episode: episode,
          );
        case 'torbox':
          final apiKey = await TorboxStorage.getTorboxApiKey();
          if (apiKey == null || apiKey.isEmpty) return null;
          return resolveViaTorbox(
            torrent,
            item,
            apiKey,
            season: season,
            episode: episode,
            isCancelled: isCancelled,
          );
        case 'pikpak':
          if (!await PikpakStorage.getPikPakEnabled()) return null;
          return resolveViaPikPak(
            torrent,
            item,
            season: season,
            episode: episode,
            isCancelled: isCancelled,
          );
        case 'premiumize':
          final apiKey = await PremiumizeStorage.getPremiumizeApiKey();
          if (apiKey == null || apiKey.isEmpty) return null;
          return resolveViaPremiumize(
            torrent,
            item,
            apiKey,
            season: season,
            episode: episode,
          );
        case 'alldebrid':
          final apiKey = await AllDebridStorage.getAllDebridApiKey();
          if (apiKey == null || apiKey.isEmpty) return null;
          return _resolveViaAllDebrid(
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
        await _trashRejectedPikPakItem(preparedForCleanup);
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
                                return computeStartProgress(
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
