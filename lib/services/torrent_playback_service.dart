import 'dart:async';
import 'dart:io';

import 'package:debrify/features/sources/application/source_candidate_checks.dart';
import 'package:debrify/features/sources/application/source_candidate_ranking.dart';
import 'package:debrify/features/sources/application/source_filter_ladder.dart';
import 'package:debrify/features/sources/application/source_probing.dart';
import 'package:debrify/features/sources/application/source_provider_config.dart';
import 'package:debrify/features/sources/data/curated_source_search.dart';
import 'package:debrify/features/sources/data/recovery_source_resolution.dart';
import 'package:debrify/features/sources/data/source_movie_fetcher.dart';
import 'package:debrify/features/sources/data/source_series_fetcher.dart';
import 'package:debrify/features/sources/models/playback_cancel_token.dart';
import 'package:debrify/features/sources/models/resolved_source.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/automatic_play_selection.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/provider_accepted_actions.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/provider_action_menu.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_binding_actions.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_loading_overlays.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_next_episode.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_play_action.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_player_args.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_player_launch.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_provider_choice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/sources/data/automatic_source_bindings.dart';
import '../features/sources/data/manual_source_preparation.dart';
import '../features/sources/data/pikpak_source_preparation.dart';
import '../features/sources/data/provider_cloud_source.dart';
import '../features/sources/data/source_acquisition.dart';
import '../features/sources/data/source_acquisition_cleanup.dart';
import '../features/sources/data/source_magnet.dart';
import '../features/sources/data/source_single_episode.dart';
import '../models/playback_meta.dart';
import '../models/profiles/profile_policy.dart';
import '../models/quick_play_rules.dart';
import '../models/torrent.dart';
import '../screens/video_player/models/playlist_entry.dart';
import '../utils/file_utils.dart';
import '../utils/filter_ladder.dart';
import '../utils/torrent_coverage_detector.dart';
import '../widgets/debrify_tv_channel_add_bridge.dart';
import '../widgets/pipeline_loading_overlay.dart';
import 'alldebrid_service.dart';
import 'android_local_source_service.dart';
import 'debrid_service.dart';
import 'direct_source_authorization.dart';
import 'failed_saved_source.dart';
import 'iptv_source_search.dart';
import 'local_bound_source_service.dart';
import 'media_server_service.dart';
import 'profiles/profile_policy_guard.dart';
import 'profiles/profile_session_memory.dart';
import 'resolved_playback_link_cache.dart';
import 'series_source_fetcher.dart';
import 'series_source_service.dart';
import 'source_selection_diagnostics.dart';
import 'storage_service.dart';
import 'stream_url_validator.dart';
import 'stremio_service.dart';
import 'video_player_launcher.dart';

export '../models/playback_meta.dart';

/// Isolated "add a chosen torrent to debrid → do the configured post-torrent
/// action" flow, composed ONLY from service-layer primitives.
///
/// Deliberately independent of the Home screen's ~2k-line inline engine so the
/// Search tab can play/download/queue without any risk of regressing Home.
/// Reimplements the small dialog UIs (not-cached, chooser) since those are
/// Home-private; everything else calls the shared services directly.
///
/// Multi-file season packs open as a playlist for all providers — TorBox /
/// Premiumize / AllDebrid built here, RD + PikPak ported verbatim from Home's
/// proven builders. The launcher lazily resolves each non-start entry.
/// Channel / advanced-metadata are follow-up slices.
class TorrentPlaybackService {
  const TorrentPlaybackService._();

  /// Add [torrent] to the resolved provider and run the user's post-torrent
  /// action (choose / play / download / playlist / open / none / copy).
  /// [forcePlay] overrides the setting to play (used by "auto-best" play).
  static Future<void> activateTorrent(
    BuildContext context,
    Torrent torrent, {
    bool forcePlay = false,
    PlaybackMeta? meta,
    List<Torrent>? sources,
    int sourceIndex = 0,
    String searchKeyword = '',
    AutomaticSourceBindings? sourceBindings,
  }) async {
    final bindingOwner = sourceBindings ?? AutomaticSourceBindings.capture();
    if (!context.mounted || !bindingOwner.isCurrent) return;
    logSourceSelection(
      'manual_pick',
      source: torrent,
      index: sourceIndex,
      season: meta?.season,
      episode: meta?.episode,
    );
    if (IptvSourceSearch.isDeferredXtreamSeries(torrent)) {
      final resolution = await IptvSourceSearch.resolveXtreamSeriesEpisode(
        torrent,
        season: meta?.season,
        episode: meta?.episode,
      );
      if (!context.mounted || !bindingOwner.isCurrent) return;
      if (resolution.source == null) {
        final target = meta?.season == null || meta?.episode == null
            ? 'This episode'
            : 'S${meta!.season.toString().padLeft(2, '0')}E${meta.episode.toString().padLeft(2, '0')}';
        SourceLoadingOverlays.snack(
          context,
          resolution.status == IptvEpisodeResolutionStatus.missing
              ? '$target is not available in this IPTV series.'
              : 'Could not check this IPTV series. Try again.',
        );
        return;
      }
      final resolved = resolution.source!;
      if (sources != null && sources.isNotEmpty) {
        final updated = List<Torrent>.from(sources);
        final index = sourceIndex.clamp(0, updated.length - 1);
        updated[index] = resolved;
        sources = updated;
      }
      torrent = resolved;
    }
    try {
      await DirectSourceAuthorization.authorize(torrent);
    } catch (_) {
      if (context.mounted && bindingOwner.isCurrent) {
        SourceLoadingOverlays.snack(context, 'IPTV connection changed. Search sources again.');
      }
      return;
    }
    if (!context.mounted || !bindingOwner.isCurrent) return;
    // Direct-URL addon streams bypass debrid entirely. Content metadata and
    // the in-player Sources switcher ride along (matching Home's
    // _playDirectStream) so series streams get Continue Watching, subtitles,
    // source switching, and the Next Episode hand-back. No provider is
    // involved, so the advance goes bound-sources → addon-stream flow.
    if (torrent.streamType == StreamType.directUrl &&
        (torrent.directUrl?.isNotEmpty ?? false)) {
      final resolverProvider = await SourceProviderConfig.defaultConfiguredProvider(
        canContinue: () => context.mounted && bindingOwner.isCurrent,
      );
      if (!context.mounted || !bindingOwner.isCurrent) return;
      final fetcher = meta?.contentType == 'movie'
          ? SourceMovieFetcher.movieFetcherFor(meta: meta)
          : SourceSeriesFetcher.seriesFetcherFor(meta: meta, episodesFetched: sources != null);
      // Even a one-row launch carries its source descriptor into the player:
      // the validated-source callback is deliberately downstream of the
      // decoder gate, so this binds the link that ACTUALLY rendered rather
      // than the row the user merely selected.
      final launchSources = sources == null || sources.isEmpty
          ? <Torrent>[torrent]
          : sources;
      final launchSourceIndex = sources == null || sources.isEmpty
          ? 0
          : sourceIndex.clamp(0, launchSources.length - 1);
      final committer = SourcePlayerLaunch.validatedLaunchCommitter(
        resolverProvider ?? SeriesSource.addonDirectService,
        meta,
        sourceBindings: bindingOwner,
      );
      try {
        await VideoPlayerLauncher.push(
          context,
          SourcePlayerArgs.playerArgs(
            videoUrl: torrent.directUrl!,
            httpHeaders: torrent.httpHeaders,
            title: torrent.displayTitle,
            subtitle: torrent.source.isNotEmpty ? torrent.source : null,
            stremioSources: launchSources,
            stremioCurrentSourceIndex: launchSourceIndex,
            resolveSourceToPlaylist:
                (launchSources.length > 1 || fetcher != null)
                ? SourcePlayerLaunch.lazyProviderResolver(committer)
                : null,
            startupFailoverEnabled: true,
            startupResolverProvider: resolverProvider,
            onStremioSourceCommitted: committer.call,
            seriesSourceFetcher: fetcher,
            meta: meta,
          ),
          retainSourceSession: committer.retain,
          sourceOwner: committer.bindings.owner,
          canContinue: () => committer.isCurrent,
          onQuickPlayNextEpisode: SourceNextEpisode.nextEpisodeHandlerFor(
            context,
            meta,
            sourceBindings: bindingOwner,
          ),
        );
      } finally {
        committer.close();
      }
      return;
    }

    // External addon streams open in an external app/browser (no debrid), same
    // as Home's _openExternalStream. Both stream kinds carry their URL in
    // directUrl.
    if (torrent.streamType == StreamType.externalUrl &&
        (torrent.directUrl?.isNotEmpty ?? false)) {
      final externalAllowed = await ProfilePolicyGuard.allows(
        ProfileFeature.externalPlayers,
      );
      if (!context.mounted || !bindingOwner.isCurrent) return;
      if (!externalAllowed) {
        SourceLoadingOverlays.snack(context, 'External players are disabled for this profile.');
        return;
      }
      final uri = Uri.tryParse(torrent.directUrl!);
      if (uri == null) {
        SourceLoadingOverlays.snack(context, 'Invalid stream URL.');
        return;
      }
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok && context.mounted) {
          SourceLoadingOverlays.snack(context, 'Could not open link — no app to handle it.');
        }
      } catch (e) {
        if (context.mounted && bindingOwner.isCurrent) {
          SourceLoadingOverlays.snack(context, 'Could not open link: $e');
        }
      }
      return;
    }

    final provider = await SourceProviderChoice.pickProvider(
      context,
      canContinue: () => context.mounted && bindingOwner.isCurrent,
    );
    if (!context.mounted || !bindingOwner.isCurrent) return;
    if (provider == SourceProviderConfig.cancelled) return; // user dismissed the picker
    if (provider == null) {
      SourceLoadingOverlays.snack(context, 'No debrid provider configured. Add one in Settings.');
      return;
    }
    final magnet = await sourceMagnet(torrent);
    if (!context.mounted || !bindingOwner.isCurrent) return;
    if (magnet == null) {
      SourceLoadingOverlays.snack(context, 'This result has no magnet or infohash to play.');
      return;
    }
    final action = forcePlay ? 'play' : await ProviderAcceptedActions.postAction(provider);
    if (!context.mounted || !bindingOwner.isCurrent) return;

    final loading = SourceLoadingOverlays.showLoading(context, provider, torrent.displayTitle);
    ResolvedSource? resolved;
    Object? notCached;
    try {
      resolved = await SourceProbing.add(
        provider,
        magnet,
        torrent,
        sourceBindings: bindingOwner,
        canContinue: () => context.mounted && bindingOwner.isCurrent,
      );
    } on TorrentNotCachedException catch (e) {
      notCached = e;
    } on AllDebridTorrentNotReadyException catch (e) {
      notCached = e;
    } on TorboxSourceNotCached catch (e) {
      notCached = e;
    } on PremiumizeSourceNotCached catch (e) {
      notCached = e;
    } on PikPakSourceStillProcessing {
      loading.dismiss();
      if (context.mounted && bindingOwner.isCurrent) {
        SourceLoadingOverlays.snack(
          context,
          'Files still processing on PikPak. Check the PikPak Files page later.',
        );
      }
      return;
    } on PikPakSourceFailed {
      loading.dismiss();
      if (context.mounted && bindingOwner.isCurrent) {
        SourceLoadingOverlays.snack(context, 'Download failed on PikPak.');
      }
      return;
    } catch (e) {
      loading.dismiss();
      if (context.mounted && bindingOwner.isCurrent) {
        SourceLoadingOverlays.snack(context, 'Could not resolve source: $e');
      }
      return;
    }
    loading.dismiss();
    if (!context.mounted || !bindingOwner.isCurrent) return;

    if (notCached != null) {
      await SourceProviderChoice.handleNotCached(
        context,
        notCached,
        provider,
        magnet,
        sourceBindings: bindingOwner,
      );
      return;
    }
    if (resolved == null) {
      SourceLoadingOverlays.snack(context, 'No playable source found for this result.');
      return;
    }

    switch (action) {
      case 'none':
        SourceLoadingOverlays.snack(context, 'Torrent added to ${SourceProviderChoice.label(provider)} successfully.');
        break;
      case 'open':
        if (resolved.isRarArchive) {
          SourceLoadingOverlays.snack(context, 'Not available for RAR archives.');
        } else {
          resolved.openInTab?.call();
        }
        break;
      case 'copy':
        if (resolved.playUrl != null && resolved.playUrl!.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: resolved.playUrl!));
          if (context.mounted && bindingOwner.isCurrent) {
            SourceLoadingOverlays.snack(
              context,
              'Torrent added to ${SourceProviderChoice.label(provider)}! Download link copied to clipboard.',
            );
          }
        } else {
          SourceLoadingOverlays.snack(
            context,
            'Added to ${SourceProviderChoice.label(provider)}, but no link was available to copy.',
          );
        }
        break;
      case 'download':
        await ProviderAcceptedActions.download(
          context,
          resolved,
          torrent,
          provider,
          sourceBindings: bindingOwner,
        );
        break;
      case 'playlist':
        await ProviderAcceptedActions.addToPlaylist(
          context,
          resolved,
          torrent,
          provider,
          meta: meta,
          sourceBindings: bindingOwner,
        );
        break;
      case 'channel':
        // Saved "Add to channel" action (parity with the old screen): cache the
        // torrent into a Debrify TV channel instead of playing it. Without this
        // case the switch fell through to `default` and silently played.
        await DebrifyTvChannelAddBridge.addTorrentsToChannel(
          context,
          torrents: [torrent],
          searchKeyword: searchKeyword,
        );
        break;
      case 'choose':
        await ProviderActionMenu.showChooser(
          context,
          resolved,
          torrent,
          provider,
          magnet: magnet,
          meta: meta,
          sources: sources,
          sourceIndex: sourceIndex,
          searchKeyword: searchKeyword,

          sourceBindings: bindingOwner,
        );
        break;
      case 'play':
      default:
        await SourcePlayAction.play(
          context,
          resolved,
          torrent,
          provider: provider,
          meta: meta,
          sources: sources,
          sourceIndex: sourceIndex,

          sourceBindings: bindingOwner,
        );
        break;
    }
  }

  /// Resolve a 'local' bound source (on-device movie file or series folder) into
  /// a playable [_Resolved]. Self-heals (removes) a source whose file/folder is
  /// gone. Returns (null, hint) when unavailable so the caller falls back to
  /// search — the hint (may be null) says why, using Home's exact wording.
  static Future<(ResolvedSource?, String?)> _resolveLocalBound(
    String imdbId,
    SeriesSource source,
    PlaybackMeta meta, {
    required AutomaticSourceBindings sourceBindings,
    required bool Function() canContinue,
  }) async {
    if (AndroidLocalSourceService.isDocumentSource(source)) {
      if (!Platform.isAndroid) {
        return (
          null,
          'This local source requires access on its Android device.',
        );
      }
      try {
        final resolved = await AndroidLocalSourceService.resolve(
          source,
          season: meta.season,
          episode: meta.episode,
          series: meta.contentType == 'series',
        );
        return (
          ResolvedSource(
            title: source.torrentName,
            playUrl: resolved.playlist[resolved.startIndex].url,
            playlist: resolved.playlist,
            startIndex: resolved.startIndex,
          ),
          null,
        );
      } on LocalSourceUnavailable catch (error) {
        return (null, '${error.message} Falling back to search.');
      } on PlatformException {
        // Permission loss, detached storage and provider failures may recover.
        // Keep the binding so the user can reconnect or grant access again.
        return (
          null,
          'Local source is unavailable. Reconnect the drive or select it again. Falling back to search.',
        );
      }
    }
    final localPath = (source.localPath?.trim().isNotEmpty ?? false)
        ? source.localPath!.trim()
        : source.debridTorrentId.trim();
    if (localPath.isEmpty) return (null, null);

    final isSeries = meta.contentType == 'series' || source.isLocalSeriesFolder;
    if (isSeries) {
      if (meta.season == null || meta.episode == null) return (null, null);
      if (!await Directory(localPath).exists()) {
        await sourceBindings.removeInvalid(
          imdbId,
          source,
          canContinue: canContinue,
        );
        return (
          null,
          'Saved local folder is no longer available. Falling back to search.',
        );
      }
      final episodes = await LocalBoundSourceService.scanSeriesFolder(
        localPath,
      );
      if (episodes.isEmpty) {
        await sourceBindings.removeInvalid(
          imdbId,
          source,
          canContinue: canContinue,
        );
        return (
          null,
          'Saved local folder has no playable episodes. Falling back to search.',
        );
      }
      final targetIndex = episodes.indexWhere(
        (e) => e.season == meta.season && e.episode == meta.episode,
      );
      if (targetIndex < 0) {
        // Episode not in folder → search fallback.
        return (
          null,
          '${SourceLoadingOverlays.seLabel(meta.season!, meta.episode!)} not found in local source. Falling back to search.',
        );
      }
      final playlist = episodes
          .map(
            (e) => PlaylistEntry(
              url: Uri.file(e.file.path).toString(),
              title: e.relativePath,
              relativePath: e.relativePath,
              provider: SeriesSource.localService,
              sizeBytes: e.sizeBytes,
            ),
          )
          .toList();
      return (
        ResolvedSource(
          title: source.torrentName,
          playUrl: playlist[targetIndex].url,
          playlist: playlist,
          startIndex: targetIndex,
        ),
        null,
      );
    }

    // Movie / single local file.
    final file = File(localPath);
    final fileName = FileUtils.getFileName(localPath);
    if (!await file.exists() || !FileUtils.isVideoFile(fileName)) {
      await sourceBindings.removeInvalid(
        imdbId,
        source,
        canContinue: canContinue,
      );
      return (
        null,
        'Saved local source is no longer available. Falling back to search.',
      );
    }
    final stat = await file.stat();
    final videoUrl = (source.localUri?.trim().isNotEmpty ?? false)
        ? source.localUri!.trim()
        : Uri.file(localPath).toString();
    final title = source.torrentName.trim().isNotEmpty
        ? source.torrentName
        : fileName;
    return (
      ResolvedSource(
        title: title,
        playUrl: videoUrl,
        playlist: [
          PlaylistEntry(
            url: videoUrl,
            title: title,
            provider: SeriesSource.localService,
            sizeBytes: stat.size,
          ),
        ],
        startIndex: 0,
      ),
      null,
    );
  }

  /// Reconstruct a [Torrent] from a stored binding so it can flow through the
  /// normal add→resolve→launch pipeline (debrid dedup makes the re-add instant).
  static Torrent _torrentFromSource(SeriesSource s) {
    // Stamp coverage like the engine field-mapper does for search results —
    // a reconstructed binding otherwise has coverageType null, and the
    // player's series source tabs would file a season pack under "Episodes".
    CoverageInfo? coverage;
    try {
      coverage = TorrentCoverageDetector.detectCoverage(
        title: s.torrentName,
        infohash: s.torrentHash,
      );
    } catch (_) {}
    return Torrent(
      rowid: 0,
      infohash: s.torrentHash,
      name: s.torrentName,
      sizeBytes: 0,
      createdUnix: 0,
      seeders: 0,
      leechers: 0,
      completed: 0,
      scrapedDate: 0,
      // Both players' source sheets group by this field; empty filed the
      // binding under "Other sources". Both sheets label 'pinned' explicitly.
      source: 'pinned',
      magnetUrl:
          'magnet:?xt=urn:btih:${s.torrentHash}&dn=${Uri.encodeComponent(s.torrentName)}',
      hasRealInfoHash: true,
      coverageType: coverage?.coverageType.name,
      startSeason: coverage?.startSeason,
      endSeason: coverage?.endSeason,
      seasonNumber: coverage?.seasonNumber,
      transformedTitle: coverage?.transformedTitle,
    );
  }

  /// Resolve a hashless cloud binding from its provider-native stable id.
  /// Direct URLs are deliberately refreshed on every play.
  static Future<ResolvedSource?> _resolveProviderNativeBound(
    SeriesSource source,
    PlaybackMeta meta, {
    required AutomaticSourceBindings sourceBindings,
    required bool Function() canContinue,
  }) async {
    final result = await const ProviderCloudSource().resolve(
      source,
      meta,
      owner: sourceBindings.owner,
      canContinue: canContinue,
    );
    if (result == null) return null;
    return ResolvedSource(
      title: result.title,
      playUrl: result.playUrl,
      downloadUrls: result.downloadUrls,
      fileName: result.fileName,
      playlist: result.playlist,
      startIndex: result.startIndex,
      pikpakFileId: result.pikpakFileId,
      pikpakVideoFileId: result.pikpakVideoFileId,
    );
  }

  /// Play a pinned source directly (no search). Tries each bound source in
  /// priority order; returns true once one plays. Self-heals a source that is
  /// confirmed dead/uncached (removes it) so the caller can fall back to search.
  // TEMP(tps): moves in step 4
  static Future<bool> playViaBound(
    BuildContext context,
    String imdbId,
    List<SeriesSource> sources, {
    required String label,
    required PlaybackMeta meta,
    String? preferredProvider,
    bool skipLinkCache = false,
    required AutomaticSourceBindings sourceBindings,
  }) async {
    if (!context.mounted || !sourceBindings.isCurrent) return false;
    final usable = sources
        .where((s) => SourceProviderConfig.boundProviderSupported(s.debridService))
        .toList();
    if (usable.isEmpty) return false;

    final firstProv = SourceProviderConfig.providerFromStored(usable.first.debridService);
    final cancel = PlaybackCancelToken();
    // Bound-source play: the short (prepare → start) checklist — there's no
    // search, we're resolving an already-pinned source.
    final overlay = SourceLoadingOverlays.showPipeline(
      context,
      provider: firstProv,
      meta: meta,
      title: label,
      bound: true,
      onCancel: () => cancel.cancelled = true,
    );
    void closeLoading() => overlay.dismiss();

    // Series requests carry a concrete season+episode (gated by the caller);
    // movies leave them null and skip the episode-presence check.
    final season = meta.season;
    final episode = meta.episode;
    // Why the most recent source failed — shown once after the loop so the
    // user knows why playback fell back to a normal search (mirrors Home's
    // last-source hints in _tryPlayFromBoundSource*).
    String? fallbackHint;

    for (
      var sourcePosition = 0;
      sourcePosition < usable.length;
      sourcePosition++
    ) {
      final source = usable[sourcePosition];
      final remainingSources = usable.sublist(sourcePosition + 1);
      if (cancel.cancelled) {
        return true; // Cancel already dismissed the overlay.
      }

      if (source.isIptvDirect || source.isMediaServer) {
        fallbackHint =
            'Saved server source is unavailable. Falling back to search.';
        logIptvSourceEvent(
          'bound_playback_started',
          playlistId: source.iptvPlaylistId,
          entryKey: source.iptvEntryKey,
          catalogType: source.iptvCatalogType,
          season: meta.season,
          episode: meta.episode,
        );
        try {
          final fresh = source.isMediaServer
              ? await MediaServerService.resolvePinned(
                  source,
                  season: meta.season,
                  episode: meta.episode,
                )
              : await IptvSourceSearch.resolvePinned(
                  source,
                  title: meta.title ?? label,
                  year: meta.year,
                  season: meta.season,
                  episode: meta.episode,
                );
          if (cancel.cancelled) return true;
          final freshUrl = fresh?.directUrl;
          if (fresh != null && freshUrl != null && freshUrl.isNotEmpty) {
            final rules = await StorageService.getQuickPlayRules(
              isMovie: meta.contentType == 'movie',
            );
            if (cancel.cancelled) return true;
            var alive = true;
            if (rules.validateDirectLinks &&
                SourceCandidateRanking.shouldPreflightDirectStream(fresh)) {
              alive = await StreamUrlValidator.isPlayableVideoUrl(
                freshUrl,
                minBytes: meta.contentType == 'series'
                    ? 10 * 1024 * 1024
                    : StreamUrlValidator.minContentBytes,
                lenient: true,
                headers: fresh.httpHeaders,
              );
            }
            if (!alive) {
              logIptvSourceEvent(
                'bound_playback_rejected',
                source: fresh,
                stage: 'preflight',
                outcome: 'unplayable',
                season: meta.season,
                episode: meta.episode,
              );
              continue;
            }
            overlay.setStage(PlayLoadStage.starting);
            if (!context.mounted || !sourceBindings.isCurrent) {
              closeLoading();
              return false;
            }
            logIptvSourceEvent(
              'bound_playback_launching',
              source: fresh,
              outcome: 'resolved',
              season: meta.season,
              episode: meta.episode,
            );
            await SourcePlayerLaunch.launch(
              context,
              ResolvedSource(
                title: fresh.displayTitle,
                playUrl: freshUrl,
                downloadUrls: [freshUrl],
                fileName: fresh.displayTitle,
                httpHeaders: fresh.httpHeaders,
              ),
              fresh.displayTitle,
              provider: source.isMediaServer
                  ? SeriesSource.mediaServerService
                  : SeriesSource.iptvDirectService,
              recoveryProvider: preferredProvider,
              startupHasRemainingSavedSources: remainingSources.isNotEmpty,
              meta: meta,
              sources: [fresh],
              sourceIndex: 0,
              seriesFetcher:
                  SourceSeriesFetcher.seriesFetcherFor(meta: meta, provider: preferredProvider) ??
                  SourceMovieFetcher.movieFetcherFor(meta: meta, provider: preferredProvider),
              overlay: overlay,
              startupFailoverEnabled: true,
              onStartupSourcesExhausted: () async {
                await FailedSavedSource.cleanup(
                  removePin: () => sourceBindings.removeInvalid(
                    imdbId,
                    source,
                    canContinue: () => context.mounted && !cancel.cancelled,
                  ),
                );
                if (!context.mounted || !sourceBindings.isCurrent) return;
                await SourceBindingActions.recoverAfterBoundStartupFailure(
                  context,
                  imdbId,
                  remainingSources,
                  label: label,
                  meta: meta,
                  preferredProvider: preferredProvider,

                  sourceBindings: sourceBindings,
                );
              },

              sourceBindings: sourceBindings,
            );
            return true;
          }
        } catch (_) {
          // A stale/temporarily unavailable catalog falls through to other
          // pins and normal search without deleting the durable descriptor.
        }
        if (!context.mounted || !sourceBindings.isCurrent) {
          closeLoading();
          return false;
        }
        continue;
      }

      // Addon-direct pins store provenance, never the expiring URL. Resolve
      // the current movie/episode endpoint now and launch the freshly returned
      // link. A rejected playable link is unpinned and evicted from the cache;
      // recovery moves to the remaining pins, then a fresh search. There is no
      // persistent blacklist: fresh search/manual selection may find it again.
      if (source.isAddonDirect) {
        logSourceSelection(
          'saved_direct_attempt',
          index: sourcePosition,
          season: meta.season,
          episode: meta.episode,
          reason: source.bingeGroup?.isNotEmpty == true
              ? 'binge_group'
              : 'stream_identity',
        );
        fallbackHint =
            'Saved direct source is unavailable. Falling back to search.';
        try {
          Future<Torrent?> refresh() async {
            final originVideoId = await CuratedSourceSearch.originEpisodeVideoId(
              meta,
              meta.season,
              meta.episode,
            );
            if (meta.hasStremioEpisodeIdentity && originVideoId == null) {
              return null;
            }
            return StremioService.instance.resolvePinnedDirectStream(
              addonId: source.addonId!,
              addonKey: source.addonKey!,
              streamKey: source.streamKey ?? '',
              bingeGroup: source.bingeGroup,
              originCatalogId: source.addonCatalogId,
              originVideoId: originVideoId,
              streamIndex: source.streamIndex ?? 0,
              type: meta.contentType == 'movie' ? 'movie' : 'series',
              contentId: imdbId,
              season: meta.season,
              episode: meta.episode,
            );
          }

          final installed = await StremioService.instance.getAddons();
          final cacheAllowed = installed.any(
            (addon) =>
                addon.enabled &&
                addon.supportsStreams &&
                addon.sourceBindingKey == source.addonKey,
          );
          final cached = !cacheAllowed || skipLinkCache
              ? null
              : await ResolvedPlaybackLinkCache.get(
                  id: imdbId,
                  type: meta.contentType ?? 'series',
                  season: meta.season,
                  episode: meta.episode,
                  pin: source,
                );
          var usingCache = cached != null;
          var fresh = cached ?? await refresh();
          logSourceSelection(
            'saved_direct_resolved',
            source: fresh,
            season: meta.season,
            episode: meta.episode,
            reason: fresh == null
                ? 'no_match'
                : usingCache
                ? 'cached_link'
                : 'addon_refresh',
          );
          if (cancel.cancelled) return true;
          var freshUrl = fresh?.directUrl;
          if (fresh != null && freshUrl != null && freshUrl.isNotEmpty) {
            final rules = await StorageService.getQuickPlayRules(
              isMovie: meta.contentType == 'movie',
            );
            if (cancel.cancelled) return true;
            if (rules.validateDirectLinks &&
                SourceCandidateRanking.shouldPreflightDirectStream(fresh)) {
              final minBytes = meta.contentType == 'series'
                  ? 10 * 1024 * 1024
                  : StreamUrlValidator.minContentBytes;
              var alive = await StreamUrlValidator.isPlayableVideoUrl(
                freshUrl,
                minBytes: minBytes,
                lenient: true,
                headers: fresh.httpHeaders,
              );
              if (cancel.cancelled) return true;
              if (!alive && usingCache) {
                await sourceBindings.removeCachedLink(
                  canContinue: () => context.mounted && !cancel.cancelled,
                  id: imdbId,
                  type: meta.contentType ?? 'series',
                  season: meta.season,
                  episode: meta.episode,
                  pin: source,
                );
                usingCache = false;
                fresh = await refresh();
                freshUrl = fresh?.directUrl;
                if (fresh == null || freshUrl == null || freshUrl.isEmpty)
                  continue;
                alive =
                    !SourceCandidateRanking.shouldPreflightDirectStream(fresh) ||
                    await StreamUrlValidator.isPlayableVideoUrl(
                      freshUrl,
                      minBytes: minBytes,
                      lenient: true,
                      headers: fresh.httpHeaders,
                    );
                if (cancel.cancelled) return true;
              }
              if (!alive) {
                await sourceBindings.removeInvalid(
                  imdbId,
                  source,
                  canContinue: () => context.mounted && !cancel.cancelled,
                );
                await sourceBindings.removeCachedLink(
                  canContinue: () => context.mounted && !cancel.cancelled,
                  id: imdbId,
                  type: meta.contentType ?? 'series',
                  season: meta.season,
                  episode: meta.episode,
                  pin: source,
                );
                continue;
              }
            }
            overlay.setStage(PlayLoadStage.starting);
            if (!context.mounted || !sourceBindings.isCurrent) {
              closeLoading();
              return false;
            }
            await SourcePlayerLaunch.launch(
              context,
              ResolvedSource(
                title: fresh.displayTitle,
                playUrl: freshUrl,
                downloadUrls: [freshUrl],
                fileName: fresh.displayTitle,
                httpHeaders: fresh.httpHeaders,
              ),
              fresh.displayTitle,
              provider: SeriesSource.addonDirectService,
              recoveryProvider: preferredProvider,
              startupHasRemainingSavedSources: remainingSources.isNotEmpty,
              meta: meta,
              sources: [fresh],
              sourceIndex: 0,
              seriesFetcher:
                  SourceSeriesFetcher.seriesFetcherFor(meta: meta, provider: preferredProvider) ??
                  SourceMovieFetcher.movieFetcherFor(meta: meta, provider: preferredProvider),
              overlay: overlay,
              startupFailoverEnabled: true,
              onStartupSourcesExhausted: () async {
                await FailedSavedSource.cleanup(
                  removePin: () => sourceBindings.removeInvalid(
                    imdbId,
                    source,
                    canContinue: () => context.mounted && !cancel.cancelled,
                  ),
                  removeCache: () => sourceBindings.removeCachedLink(
                    canContinue: () => context.mounted && !cancel.cancelled,
                    id: imdbId,
                    type: meta.contentType ?? 'series',
                    season: meta.season,
                    episode: meta.episode,
                    pin: source,
                  ),
                );
                if (!context.mounted || !sourceBindings.isCurrent) return;
                await SourceBindingActions.recoverAfterBoundStartupFailure(
                  context,
                  imdbId,
                  remainingSources,
                  label: label,
                  meta: meta,
                  preferredProvider: preferredProvider,

                  sourceBindings: sourceBindings,
                );
              },

              sourceBindings: sourceBindings,
            );
            return true;
          }
        } catch (_) {
          // Fail soft and continue through lower-priority pins/search.
        }
        if (!context.mounted || !sourceBindings.isCurrent) {
          closeLoading();
          return false;
        }
        continue;
      }

      // Cheap skip: a bound DEBRID source whose name is a single specific
      // episode can only serve that episode — skip it (no debrid round-trip)
      // when a different episode is requested, so a series pinned only as
      // single episodes doesn't churn through every binding on each play.
      // Packs and ambiguous names fall through to the normal resolve + episode
      // check. Local sources are excluded: a series FOLDER resolves the
      // episode internally regardless of its name, and resolving is free.
      if (season != null &&
          episode != null &&
          source.debridService != SeriesSource.localService) {
        final se = singleSourceEpisode(source.torrentName);
        if (se != null && (se.$1 != season || se.$2 != episode)) {
          continue;
        }
      }

      // Local (on-device file/folder) sources resolve without a debrid add.
      if (source.debridService == SeriesSource.localService) {
        final (r, hint) = await _resolveLocalBound(
          imdbId,
          source,
          meta,
          sourceBindings: sourceBindings,
          canContinue: () => context.mounted && !cancel.cancelled,
        );
        if (cancel.cancelled) return true;
        if (r != null) {
          overlay.setStage(PlayLoadStage.starting);
          if (!context.mounted || !sourceBindings.isCurrent) {
            closeLoading();
            return false;
          }
          // Loader stays up through the launch prep; _launch has it dismissed
          // when the player takes the screen.
          await SourcePlayerLaunch.launch(
            context,
            r,
            r.title,
            provider: SeriesSource.localService,
            startupHasRemainingSavedSources: remainingSources.isNotEmpty,
            meta: meta,
            overlay: overlay,
            startupFailoverEnabled: true,
            onStartupSourcesExhausted: () async {
              await FailedSavedSource.cleanup(
                removePin: () => sourceBindings.removeInvalid(
                  imdbId,
                  source,
                  canContinue: () => context.mounted && !cancel.cancelled,
                ),
              );
              await SourceBindingActions.recoverAfterBoundStartupFailure(
                context,
                imdbId,
                remainingSources,
                label: label,
                meta: meta,
                preferredProvider: preferredProvider,

                sourceBindings: sourceBindings,
              );
            },

            sourceBindings: sourceBindings,
          );
          return true;
        }
        if (!context.mounted || !sourceBindings.isCurrent) {
          closeLoading();
          return false;
        }
        // Always overwrite (even with null) so the hint reflects THIS
        // source's failure, never a stale one from an earlier attempt.
        fallbackHint = hint;
        continue; // unavailable / episode not found → try next source
      }

      final prov = SourceProviderConfig.providerFromStored(source.debridService);
      final nativeCloud = source.isProviderNativeCloud;
      final t = nativeCloud ? null : _torrentFromSource(source);
      ResolvedSource? res;
      // Default reason if this attempt fails without a more specific one
      // (no magnet, empty play URL, not-cached, transient error) — Home's
      // generic wording. Overwritten below when we know more.
      fallbackHint =
          'Saved source is no longer available. Falling back to search.';
      try {
        final ResolvedSource? r;
        if (nativeCloud) {
          r = await _resolveProviderNativeBound(
            source,
            meta,
            sourceBindings: sourceBindings,
            canContinue: () => context.mounted && !cancel.cancelled,
          );
        } else {
          final magnet = await sourceMagnet(t!);
          if (magnet == null) continue;
          if (cancel.cancelled) return true;
          r = await SourceProbing.add(
            prov,
            magnet,
            t,
            sourceBindings: sourceBindings,
            canContinue: () =>
                context.mounted &&
                sourceBindings.isCurrent &&
                !cancel.cancelled,
          );
        }
        if (r != null && r.playUrl != null && r.playUrl!.isNotEmpty) {
          if (season != null &&
              episode != null &&
              !SourceCandidateChecks.resolvedHasEpisode(r, season, episode)) {
            // Pack resolved fine but doesn't contain the requested episode
            // (e.g. an S1–S3 binding asked for S4E1) — skip it, matching
            // Home, instead of letting the player silently start a
            // different file. Keep the binding: it's still valid for the
            // seasons it covers.
            fallbackHint =
                '${SourceLoadingOverlays.seLabel(season, episode)} not in saved sources. Use Edit Source to change them.';
            // RD's addMagnet / PikPak's addOfflineDownload created a fresh
            // account entry just for this attempt — delete it so repeated
            // fallbacks don't pile up orphans. TorBox/AllDebrid dedup the
            // add to an existing entry (deleting could break other bindings)
            // and Premiumize adds nothing, so those are left alone.
            if (!nativeCloud) {
              await cleanupWrongEpisode(
                prov,
                owner: sourceBindings.owner,
                rdTorrentId: r.rdTorrentId,
                pikpakFileId: r.pikpakFileId,
              );
            }
          } else {
            res = r;
          }
        }
      } on TorrentNotCachedException catch (e) {
        // Bound RD source is no longer cached → self-heal and try the next.
        await cleanupRejectedSource(e, owner: sourceBindings.owner);
        await sourceBindings.removeInvalid(
          imdbId,
          source,
          canContinue: () => context.mounted && !cancel.cancelled,
        );
      } on AllDebridTorrentNotReadyException catch (e) {
        // Transient (still resolving) — keep the binding, just fail this attempt.
        await cleanupRejectedSource(e, owner: sourceBindings.owner);
        fallbackHint =
            'Saved source is not ready on AllDebrid. Falling back to search.';
      } catch (_) {
        // TorBox/Premiumize uncached or transient — keep binding, try next.
      }
      if (cancel.cancelled) return true;
      if (res != null) {
        overlay.setStage(PlayLoadStage.starting);
        if (!context.mounted || !sourceBindings.isCurrent) {
          closeLoading();
          return false;
        }
        // Loader stays up through the launch prep; _launch has it dismissed
        // when the player takes the screen.
        await SourcePlayerLaunch.launch(
          context,
          res,
          nativeCloud ? source.torrentName : t!.displayTitle,
          provider: prov,
          startupHasRemainingSavedSources: remainingSources.isNotEmpty,
          meta: meta,
          sources: nativeCloud ? null : [t!],
          sourceIndex: 0,
          // Bound play searched NOTHING — every applicable "Load more"
          // shows. Each factory self-gates on content type, so exactly one
          // (or neither, for non-tt ids) is non-null.
          seriesFetcher: nativeCloud
              ? null
              : (SourceSeriesFetcher.seriesFetcherFor(meta: meta, provider: prov) ??
                    SourceMovieFetcher.movieFetcherFor(meta: meta, provider: prov)),
          overlay: overlay,
          startupFailoverEnabled: true,
          onStartupSourcesExhausted: () async {
            await FailedSavedSource.cleanup(
              removePin: () => sourceBindings.removeInvalid(
                imdbId,
                source,
                canContinue: () => context.mounted && !cancel.cancelled,
              ),
            );
            await SourceBindingActions.recoverAfterBoundStartupFailure(
              context,
              imdbId,
              remainingSources,
              label: label,
              meta: meta,
              preferredProvider: preferredProvider,

              sourceBindings: sourceBindings,
            );
          },

          sourceBindings: sourceBindings,
        );
        return true;
      }
      if (!context.mounted || !sourceBindings.isCurrent) {
        closeLoading();
        return false;
      }
    }
    closeLoading();
    // Mirror Home: say why bound playback failed before the caller falls back
    // to a normal search.
    if (fallbackHint != null && context.mounted) SourceLoadingOverlays.snack(context, fallbackHint);
    return false;
  }

  static Future<void> playFromSelection(
    BuildContext context, {
    required String imdbId,
    required bool isMovie,
    int? season,
    int? episode,
    required PlaybackMeta meta,
    // Skip the provider picker and use this provider directly — set by the
    // next-episode auto-advance so a binge never re-prompts mid-chain.
    String? preferredProvider,
    // A player-level failure has already exhausted the applicable saved
    // sources. Recovery re-enters below the binding gate so the same failed
    // source cannot launch again in a loop.
    bool skipBoundSources = false,
    // Hands the user the manual source list for THIS selection instead of
    // auto-picking. Supplying it is what opts a call site into the user's
    // "Play button opens" preference (see [StorageService.getPlayButtonMode]):
    // only a real Play press passes an opener, so binge auto-advance and
    // post-failure recovery keep their existing no-prompt contract for free.
    VoidCallback? openSourcePicker,
    AutomaticSourceBindings? sourceBindings,
  }) => AutomaticPlaySelection.playFromSelection(context, imdbId: imdbId, isMovie: isMovie, season: season, episode: episode, meta: meta, preferredProvider: preferredProvider, skipBoundSources: skipBoundSources, openSourcePicker: openSourcePicker, sourceBindings: sourceBindings);

  static PipelineLoadingOverlay showResolvingOverlay(
    BuildContext context, {
    required PlaybackMeta? meta,
    required String title,
    VoidCallback? onCancel,
  }) => SourceLoadingOverlays.showResolvingOverlay(context, meta: meta, title: title, onCancel: onCancel);

  static Future<bool> bindSource(
    BuildContext context,
    Torrent torrent, {
    required String imdbId,
    required bool isMovie,
    Future<bool> Function(SeriesSource)? saveBinding,
    bool Function()? canContinue,
    String? addonCatalogId,
    String? addonCatalogKey,
    ManualSourcePreparation preparation = const ManualSourcePreparation(),
  }) => SourceBindingActions.bindSource(context, torrent, imdbId: imdbId, isMovie: isMovie, saveBinding: saveBinding, canContinue: canContinue, addonCatalogId: addonCatalogId, addonCatalogKey: addonCatalogKey, preparation: preparation);

  static Future<bool> bindDirectSource(
    BuildContext context,
    Torrent torrent, {
    required String imdbId,
    required bool isMovie,
    Future<bool> Function(SeriesSource)? saveBinding,
    bool Function()? canContinue,
    String? addonCatalogId,
    String? addonCatalogKey,
  }) => SourceBindingActions.bindDirectSource(context, torrent, imdbId: imdbId, isMovie: isMovie, saveBinding: saveBinding, canContinue: canContinue, addonCatalogId: addonCatalogId, addonCatalogKey: addonCatalogKey);

  static Future<bool> bindIptvSource(
    BuildContext context,
    Torrent torrent, {
    required String imdbId,
    required bool isMovie,
    Future<bool> Function(SeriesSource)? saveBinding,
    bool Function()? canContinue,
  }) => SourceBindingActions.bindIptvSource(context, torrent, imdbId: imdbId, isMovie: isMovie, saveBinding: saveBinding, canContinue: canContinue);

  static Future<void> downloadDirectStream(
    BuildContext context,
    Torrent torrent,
  ) => ProviderAcceptedActions.downloadDirectStream(context, torrent);

  static bool supportsDirectStreamDownload(Torrent torrent) => ProviderAcceptedActions.supportsDirectStreamDownload(torrent);

  static SeriesSourceFetcher? seriesFetcherFor({
    required PlaybackMeta? meta,
    String? provider,
    bool packsFetched = false,
    bool episodesFetched = false,
    Future<List<Torrent>>? initialEpisodeSearch,
  }) => SourceSeriesFetcher.seriesFetcherFor(meta: meta, provider: provider, packsFetched: packsFetched, episodesFetched: episodesFetched, initialEpisodeSearch: initialEpisodeSearch);

  static Future<List<Torrent>> prepareRecoverySources(
    List<Torrent> raw, {
    required QuickPlayRules rules,
    required String? provider,
    required FilterLadder ladder,
    Future<List<Torrent>> Function(String, List<Torrent>)? cacheCheck,
  }) => RecoverySourceResolution.prepareRecoverySources(raw, rules: rules, provider: provider, ladder: ladder, cacheCheck: cacheCheck);

  static Future<List<PlaylistEntry>?> resolveRecoverySource(
    Torrent source, {
    required String? provider,
    AutomaticSourceBindings? sourceBindings,
    ProfileSessionOwner? owner,
    bool Function()? canContinue,
    int? season,
    int? episode,
  }) => RecoverySourceResolution.resolveRecoverySource(source, provider: provider, sourceBindings: sourceBindings, owner: owner, canContinue: canContinue, season: season, episode: episode);

  static Future<FilterLadder> loadLadder({
    bool includeSize = true,
    QuickPlayRules? rules,
  }) => SourceFilterLadder.loadLadder(includeSize: includeSize, rules: rules);

  static int directValidationBudgetForRules(QuickPlayRules? rules) => SourceCandidateRanking.directValidationBudgetForRules(rules);

  static bool shouldPreflightDirectStream(Torrent torrent) => SourceCandidateRanking.shouldPreflightDirectStream(torrent);
}
