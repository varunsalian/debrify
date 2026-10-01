import 'dart:async';

import 'package:debrify/features/sources/application/source_candidate_ranking.dart';
import 'package:debrify/features/sources/application/source_filter_ladder.dart';
import 'package:debrify/features/sources/application/source_probing.dart';
import 'package:debrify/features/sources/application/source_provider_config.dart';
import 'package:debrify/features/sources/data/recovery_source_resolution.dart';
import 'package:debrify/features/sources/data/source_movie_fetcher.dart';
import 'package:debrify/features/sources/data/source_series_fetcher.dart';
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
import '../features/sources/data/source_acquisition.dart';
import '../features/sources/data/source_magnet.dart';
import '../models/playback_meta.dart';
import '../models/profiles/profile_policy.dart';
import '../models/quick_play_rules.dart';
import '../models/torrent.dart';
import '../screens/video_player/models/playlist_entry.dart';
import '../utils/filter_ladder.dart';
import '../widgets/debrify_tv_channel_add_bridge.dart';
import '../widgets/pipeline_loading_overlay.dart';
import 'alldebrid_service.dart';
import 'debrid_service.dart';
import 'direct_source_authorization.dart';
import 'iptv_source_search.dart';
import 'profiles/profile_policy_guard.dart';
import 'profiles/profile_session_memory.dart';
import 'series_source_fetcher.dart';
import 'series_source_service.dart';
import 'source_selection_diagnostics.dart';
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
