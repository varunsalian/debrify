import 'dart:async';
import 'dart:io';

import 'package:debrify/features/sources/application/source_cache_ordering.dart';
import 'package:debrify/features/sources/application/source_candidate_checks.dart';
import 'package:debrify/features/sources/application/source_candidate_ranking.dart';
import 'package:debrify/features/sources/application/source_curation.dart';
import 'package:debrify/features/sources/application/source_filter_ladder.dart';
import 'package:debrify/features/sources/application/source_iptv_availability.dart';
import 'package:debrify/features/sources/application/source_probing.dart';
import 'package:debrify/features/sources/application/source_provider_config.dart';
import 'package:debrify/features/sources/application/source_search_plans.dart';
import 'package:debrify/features/sources/data/curated_source_search.dart';
import 'package:debrify/features/sources/data/iptv_quick_play_search.dart';
import 'package:debrify/features/sources/data/recovery_source_resolution.dart';
import 'package:debrify/features/sources/data/series_pack_search.dart';
import 'package:debrify/features/sources/data/source_movie_fetcher.dart';
import 'package:debrify/features/sources/data/source_series_fetcher.dart';
import 'package:debrify/features/sources/models/playback_cancel_token.dart';
import 'package:debrify/features/sources/models/resolved_source.dart';
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
import '../features/sources/data/source_binding_committer.dart';
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
import 'profiles/profile_runtime.dart';
import 'profiles/profile_session_memory.dart';
import 'resolved_playback_link_cache.dart';
import 'series_source_fetcher.dart';
import 'series_source_service.dart';
import 'source_selection_diagnostics.dart';
import 'storage_service.dart';
import 'stream_url_validator.dart';
import 'stremio_service.dart';
import 'torrent_service.dart';
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

  /// Series-auto-pin negative cache: "imdbId:season" → when to allow
  /// re-searching packs. A pack-first attempt that finds no instantly-playable
  /// pack records an entry so subsequent episodes of the SAME season (a binge,
  /// or an ongoing show with no pack yet) skip the expensive whole-series pack
  /// search instead of repeating it every play. Season remains part of the key
  /// because "no pack for S1" must not suppress an S7 pack; provider and the
  /// complete rules profile are also included so a settings/provider change
  /// takes effect immediately. In-memory + TTL means a newly-released pack is
  /// still picked up after the window (or an app restart).
  static final Map<String, DateTime> _noPackUntil = {};

  static String _noPackKey(
    String imdbId,
    int season,
    String provider,
    QuickPlayRules rules,
  ) => '$imdbId:$season:$provider:${rules.hashCode}';

  static bool _recentlyNoPack(
    String imdbId,
    int season,
    String provider,
    QuickPlayRules rules,
  ) {
    // "Do not remember" must take effect immediately, including for entries
    // recorded before the user changed this setting.
    if (rules.failedPackCacheHours <= 0) return false;
    final key = _noPackKey(imdbId, season, provider, rules);
    final until = _noPackUntil[key];
    if (until == null) return false;
    if (!DateTime.now().isBefore(until)) {
      _noPackUntil.remove(key);
      return false;
    }
    return true;
  }

  static void _markNoPack(
    String imdbId,
    int season,
    String provider,
    QuickPlayRules rules,
    Duration ttl,
  ) {
    if (ttl <= Duration.zero) return;
    // Bound the map so a long session browsing many shows can't grow it
    // without limit; drop expired entries first, then the oldest.
    final now = DateTime.now();
    _noPackUntil.removeWhere((_, until) => !now.isBefore(until));
    const cap = 200;
    if (_noPackUntil.length >= cap) {
      final oldest = _noPackUntil.entries
          .reduce((a, b) => a.value.isBefore(b.value) ? a : b)
          .key;
      _noPackUntil.remove(oldest);
    }
    _noPackUntil[_noPackKey(imdbId, season, provider, rules)] = now.add(ttl);
  }

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

  /// Catalog "Play" — auto-pick the best instantly-playable source and play it.
  /// Cache-first ordering for TorBox/Premiumize; the resolve loop cleans up any
  /// uncached torrent it probes on RD/AllDebrid so the account isn't polluted.
  static Future<void> playBest(
    BuildContext context,
    List<Torrent> torrents, {
    String? provider,
    String? title,
    PlaybackMeta? meta,
    // Non-null when the search flow already put a loader up (the search phase);
    // null for a standalone play (e.g. the catalog board), which creates one.
    PipelineLoadingOverlay? overlay,
    bool Function()? isCancelled,
    // Quick-play filter ladder (QUICK_PLAY_FILTERS_PLAN.md): ranks candidates
    // by filter strictness. Null/inactive ⇒ byte-identical legacy behavior.
    FilterLadder? ladder,
    QuickPlayRules? rules,
    // "Load more sources" backend for the player's series source tabs; rides
    // through to the launch untouched. Null ⇒ flat source list (unchanged).
    SeriesSourceFetcher? seriesFetcher,
    AutomaticSourceBindings? sourceBindings,
  }) async {
    final bindingOwner = sourceBindings ?? AutomaticSourceBindings.capture();
    if (!context.mounted || !bindingOwner.isCurrent) {
      overlay?.dismiss();
      return;
    }
    if (rules != null) {
      torrents = SourceCandidateRanking.orderCandidatesForRules(
        torrents,
        rules: rules,
        ladder: ladder,
      );
    } else if (ladder != null && ladder.isActive) {
      // Legacy callers without a profile retain their historical ordering.
      torrents = ladder.order(torrents);
    }
    final rootNav = Navigator.of(context, rootNavigator: true);
    // The play loader handle: passed in by the search flow, or created below
    // for a standalone play (e.g. the catalog board). Dismissed exactly once.
    var ov = overlay;
    void closeLoading() {
      if (ov != null) {
        ov.dismiss();
      } else if (rootNav.canPop()) {
        rootNav.pop();
      }
    }

    bool cancelled() {
      if (!context.mounted || !bindingOwner.isCurrent) {
        ov?.dismiss();
        return true;
      }
      return isCancelled?.call() ?? false;
    }

    // Plays a direct-URL addon stream instantly (no debrid needed). Content
    // metadata and the Sources switcher ride along (matching Home's
    // _playDirectStream) so series streams get Continue Watching, subtitles,
    // source switching, and the Next Episode hand-back. The advance reuses
    // [provider] when the caller resolved one (torrent chain); otherwise it
    // stays on the bound-sources → addon-stream path this play came from.
    Future<void> playDirect(Torrent direct) async {
      logSourceSelection(
        'quick_play_direct_selected',
        source: direct,
        index: torrents.indexOf(direct),
        season: meta?.season,
        episode: meta?.episode,
      );
      // The loader (when one is up) stays through the launch prep; the
      // launcher dismisses it the moment the player takes the screen, and
      // guarantees the dismissal on failure so it can never linger. The
      // finally only covers a throw BEFORE push() takes the callback (args
      // built up front for exactly that reason) — after which the launcher
      // owns the dismissal.
      final loader = ov;
      var handedToLauncher = false;
      SourceBindingCommitter? committer;
      try {
        await DirectSourceAuthorization.authorize(direct);
        final resolverProvider =
            provider ??
            await SourceProviderConfig.defaultConfiguredProvider(
              canContinue: () => context.mounted && bindingOwner.isCurrent,
            );
        if (!context.mounted || !bindingOwner.isCurrent) return;
        committer = SourcePlayerLaunch.validatedLaunchCommitter(
          resolverProvider ?? SeriesSource.addonDirectService,
          meta,
          sourceBindings: bindingOwner,
        );
        final args = SourcePlayerArgs.playerArgs(
          videoUrl: direct.directUrl!,
          httpHeaders: direct.httpHeaders,
          title: direct.displayTitle,
          subtitle: direct.source.isNotEmpty ? direct.source : null,
          stremioSources: torrents,
          stremioCurrentSourceIndex: torrents.indexOf(direct),
          resolveSourceToPlaylist:
              (torrents.length > 1 || seriesFetcher != null)
              ? (resolverProvider == null
                    ? SourcePlayerLaunch.lazyProviderResolver(committer)
                    : SourcePlayerLaunch.resolverFor(resolverProvider, committer))
              : null,
          startupFailoverEnabled: true,
          startupResolverProvider: resolverProvider,
          onStremioSourceCommitted: committer.call,
          seriesSourceFetcher: seriesFetcher,
          meta: meta,
        );
        final nextEpisodeHandler = SourceNextEpisode.nextEpisodeHandlerFor(
          context,
          meta,
          provider: provider,

          sourceBindings: bindingOwner,
        );
        handedToLauncher = loader != null;
        await VideoPlayerLauncher.push(
          context,
          args,
          retainSourceSession: committer.retain,
          sourceOwner: committer.bindings.owner,
          canContinue: () => committer!.isCurrent,
          onPlayerHandoff: loader?.dismiss,
          onQuickPlayNextEpisode: nextEpisodeHandler,
        );
      } finally {
        committer?.close();
        if (!handedToLauncher) loader?.dismiss();
      }
    }

    // Direct links carry no implicit validation (a torrent's debrid resolve
    // IS its probe), and dead hosts love serving tiny placeholder videos with
    // a 200 — so every direct play below runs through a HEAD check first
    // (same validator Stremio TV always used) and steps to the next candidate
    // on failure. VOD ONLY: live channels (non-movie/series catalog plays)
    // routinely stream without a content-length and would all read as dead —
    // they keep the unvalidated instant play. The budget bounds worst-case
    // added latency; once spent, remaining candidates play unvalidated (the
    // pre-validation behavior), so validation can only ever improve a play,
    // never lose one.
    final validatableVod =
        meta?.contentType == 'movie' || meta?.contentType == 'series';
    // Real sub-50MB episodes exist (480p / anime shorts) — the movie floor
    // would false-negative them; genuine error-placeholders are under ~5MB.
    final minStreamBytes = meta?.contentType == 'series'
        ? 10 * 1024 * 1024
        : StreamUrlValidator.minContentBytes;
    final deadDirectUrls = <String>{};
    var validationBudget = SourceCandidateRanking.directValidationBudgetForRules(rules);
    final lazyIptvResolutions = <String, Future<IptvEpisodeResolution>>{};
    final lazyIptvDeadline = DateTime.now().add(SourceIptvAvailability.iptvQuickPlaySearchTimeout);
    Future<Torrent?> resolveDirect(Torrent t) async {
      if (!IptvSourceSearch.isDeferredXtreamSeries(t)) return t;
      final resolution = await lazyIptvResolutions.putIfAbsent(t.infohash, () {
        final remaining = lazyIptvDeadline.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          return Future.value(
            const IptvEpisodeResolution(
              IptvEpisodeResolutionStatus.unavailable,
            ),
          );
        }
        return IptvSourceSearch.resolveXtreamSeriesEpisode(
          t,
          season: meta?.season,
          episode: meta?.episode,
        ).timeout(
          remaining,
          onTimeout: () => const IptvEpisodeResolution(
            IptvEpisodeResolutionStatus.unavailable,
          ),
        );
      });
      final resolved = resolution.source;
      if (resolved == null) {
        logIptvSourceEvent(
          'quick_play_candidate_rejected',
          source: t,
          stage: 'episode_resolution',
          outcome: resolution.status.name,
          season: meta?.season,
          episode: meta?.episode,
        );
        return null;
      }
      final index = torrents.indexOf(t);
      if (index >= 0) torrents[index] = resolved;
      return resolved;
    }

    Future<Torrent?> directLooksAlive(Torrent candidate) async {
      final t = await resolveDirect(candidate);
      if (t == null) return null;
      try {
        await DirectSourceAuthorization.authorize(t);
      } catch (_) {
        return null;
      }
      logSourceSelection(
        'quick_play_direct_candidate',
        source: t,
        index: torrents.indexOf(t),
        season: meta?.season,
        episode: meta?.episode,
      );
      if (rules?.validateDirectLinks == false) return t;
      if (!validatableVod) return t;
      // AIOStreams/debrid proxy URLs can be single-use or bind themselves to
      // the address family of the first request. Probing one through Dart's
      // HTTP stack and then opening it through media-kit/ExoPlayer can turn a
      // healthy link into a provider-generated "Wrong IP" slate (IPv6 HEAD,
      // IPv4 playback). These URLs must be opened first by the real player;
      // its startup gate owns failure detection and candidate failover.
      if (!SourceCandidateRanking.shouldPreflightDirectStream(t)) {
        final bypassReason = IptvSourceSearch.owns(t)
            ? 'iptv_player_validation'
            : 'ip_bound_addon';
        debugPrint(
          '[StartupFailover] event=preflight_bypass platform=flutter '
          'reason=$bypassReason addon=${t.stremioAddonId ?? '-'}',
        );
        return t;
      }
      final url = t.directUrl!;
      if (deadDirectUrls.contains(SourceCandidateChecks.directValidationKey(t))) {
        debugPrint(
          '[StartupFailover] event=preflight_result platform=flutter '
          'ok=false reason=known_dead',
        );
        return null;
      }
      if (validationBudget <= 0) {
        debugPrint(
          '[StartupFailover] event=preflight_bypass platform=flutter '
          'reason=budget_exhausted',
        );
        return t; // budget spent — trust it
      }
      validationBudget--;
      debugPrint(
        '[StartupFailover] event=preflight_begin platform=flutter '
        'remainingBudget=$validationBudget minBytes=$minStreamBytes',
      );
      // Lenient: only positive evidence of death rejects — HEAD-refusing
      // hosts and length-less 2xx responses give no signal and whole CDNs
      // fail them identically, which would kill every candidate at once.
      final alive = await StreamUrlValidator.isPlayableVideoUrl(
        url,
        minBytes: minStreamBytes,
        lenient: true,
        headers: t.httpHeaders,
      );
      logSourceSelection(
        'quick_play_direct_preflight',
        source: t,
        reason: alive ? 'accepted_for_player_validation' : 'rejected',
      );
      debugPrint(
        '[StartupFailover] event=preflight_result platform=flutter '
        'ok=$alive remainingBudget=$validationBudget',
      );
      if (!alive) {
        deadDirectUrls.add(SourceCandidateChecks.directValidationKey(t));
        ov?.setNote('Skipped a dead stream link — trying the next source…');
      }
      return alive ? t : null;
    }

    // Walks every direct stream in (tier-ordered) list order and plays the
    // first one that validates. Returns true when it handled the play (or the
    // user cancelled mid-walk); false when no direct stream survived.
    Future<bool> playFirstAliveDirect() async {
      for (final t in torrents) {
        final isDirect = SourceCandidateChecks.isDirectCandidate(t);
        if (!isDirect) continue;
        if (cancelled()) return true; // overlay dismissed by the Cancel tap
        final playable = await directLooksAlive(t);
        if (playable != null) {
          if (cancelled()) return true;
          await playDirect(playable);
          return true;
        }
      }
      return false;
    }

    final bool tiered = ladder != null && ladder.isActive;

    // Exact-order is deliberately isolated from the legacy/direct-first path:
    // walk the provider/transport-ordered list and attempt each playable entry
    // in place. Provider-specific torrent preparation happens when the walk
    // first reaches a torrent, so a leading direct stream still plays without
    // prompting for (or waiting on) a debrid provider.
    if (rules?.ranking == QuickPlayRanking.exactOrder) {
      var exactSources = List<Torrent>.from(torrents);
      var strictProvider = provider;
      var providerWasChecked = provider != null;
      var providerUnavailable = false;
      var providerPrepared = false;
      var pikPakTorrentProbed = false;
      var attempts = 0;
      var limit = rules!.tryNextOnFailure ? rules.maxAttempts : 1;
      for (
        var candidateIndex = 0;
        candidateIndex < exactSources.length;
        candidateIndex++
      ) {
        final source = exactSources[candidateIndex];
        if (cancelled()) break;
        if (source.streamType == StreamType.externalUrl) continue;
        final isDirect = SourceCandidateChecks.isDirectCandidate(source);
        final isTorrent = SourceCandidateChecks.hasAcquisition(source);
        if (!isDirect && !isTorrent) continue;

        if (isDirect) {
          final playable = await directLooksAlive(source);
          if (playable != null) {
            if (cancelled()) return;
            await playDirect(playable);
            return;
          }
          continue;
        }

        if (!context.mounted || !bindingOwner.isCurrent) {
          if (ov != null) closeLoading();
          return;
        }
        if (!providerWasChecked) {
          strictProvider = await SourceProviderChoice.pickProvider(
            context,
            canContinue: () => context.mounted && bindingOwner.isCurrent,
          );
          providerWasChecked = true;
          providerUnavailable = strictProvider == null;
        }
        if (!context.mounted || !bindingOwner.isCurrent) {
          if (ov != null) closeLoading();
          return;
        }
        if (strictProvider == SourceProviderConfig.cancelled) {
          if (ov != null) closeLoading();
          return;
        }
        // A torrent that cannot be attempted is not a failed source and must
        // not consume the result budget or hide a provider-free direct link
        // later in the exact returned order.
        if (strictProvider == null) continue;

        if (!providerPrepared) {
          var preparedTorrents = exactSources
              .where(
                (t) => t.streamType == StreamType.torrent && SourceCandidateChecks.hasAcquisition(t),
              )
              .toList();
          if (strictProvider == 'torbox' || strictProvider == 'premiumize') {
            ov ??= SourceLoadingOverlays.showPipeline(
              context,
              provider: strictProvider,
              meta: meta,
              title: title ?? source.displayTitle,
            );
            ov.setStage(
              PlayLoadStage.searching,
              sourceCount: preparedTorrents.length,
            );
            ov.setStage(PlayLoadStage.cacheCheck);
            preparedTorrents = await SourceCacheOrdering.cacheFirst(
              strictProvider,
              preparedTorrents,
            );
            // ignore: invalid_use_of_visible_for_testing_member
            preparedTorrents = SourceCandidateRanking.orderCacheCheckedCandidatesForRules(
              preparedTorrents,
              rules: rules,
              ladder: ladder,
            );
            if (!context.mounted || !bindingOwner.isCurrent) {
              closeLoading();
              return;
            }
            if (cancelled()) return;
          }
          if (tiered) {
            // ignore: invalid_use_of_visible_for_testing_member
            final (safeTorrents, safeAttempts) = SourceProbing.packTopSafety(
              preparedTorrents,
              provider: strictProvider,
              ladder: ladder,
              season: meta?.season,
              episode: meta?.episode,
            );
            preparedTorrents = safeTorrents;
            if (safeAttempts > limit) limit = safeAttempts;
          }
          // ignore: invalid_use_of_visible_for_testing_member
          exactSources = SourceCandidateRanking.mergePreparedTorrentOrder(
            exactSources,
            preparedTorrents,
          );
          torrents = exactSources;
          providerPrepared = true;
          // Cache-first and PikPak safety may have changed the first torrent.
          // Restart so the prepared order, including any leading direct rows,
          // is the only order consumed by the attempt budget.
          candidateIndex = -1;
          continue;
        }

        // maxAttempts caps debrid acquisition attempts. Keep walking past the
        // cap so a provider-free direct stream later in the returned order can
        // still rescue playback, as it does in the legacy selection path.
        if (attempts >= limit) continue;
        // PikPak's one-probe safety is per PLAY, not per `_probeCandidates`
        // invocation. Keep walking so a later direct link can still play, but
        // never queue a second cloud download during this exact-order pass.
        if (strictProvider == 'pikpak' && pikPakTorrentProbed) continue;
        attempts++;
        if (strictProvider == 'pikpak') pikPakTorrentProbed = true;
        ov ??= SourceLoadingOverlays.showPipeline(
          context,
          provider: strictProvider,
          meta: meta,
          title: title ?? source.displayTitle,
        );
        ov.setStage(PlayLoadStage.preparing);
        final (resolved, winner) = await SourceProbing.probeCandidates(
          strictProvider,
          [source],
          sourceBindings: bindingOwner,
          season: meta?.season,
          episode: meta?.episode,
          rules: rules.copyWith(tryNextOnFailure: false, maxAttempts: 1),
          isCancelled: cancelled,
        );
        if (!context.mounted || !bindingOwner.isCurrent) {
          closeLoading();
          return;
        }
        if (resolved == null || winner == null) continue;
        if (cancelled()) return;
        ov.setStage(PlayLoadStage.starting);
        await SourcePlayerLaunch.launch(
          context,
          resolved,
          winner.displayTitle,
          provider: strictProvider,
          meta: meta,
          sources: torrents,
          sourceIndex: torrents.indexOf(winner),
          seriesFetcher: seriesFetcher,
          overlay: ov,
          startupFailoverEnabled: true,

          sourceBindings: bindingOwner,
        );
        return;
      }
      if (ov != null) closeLoading();
      if (context.mounted) {
        SourceLoadingOverlays.snack(
          context,
          providerUnavailable
              ? 'No direct stream played. Add a debrid provider in Settings for torrent sources.'
              : 'No source in the selected order was instantly playable.',
        );
      }
      return;
    }

    // A direct-URL addon stream, if present, is the cheapest instant play — and
    // needs no debrid provider, so play it before prompting for one. This is the
    // IPTV / non-IMDb catalog path (streams come straight from the addon).
    // With an active ladder, it plays NOW only from the best PLAYABLE tier
    // (a full-match torrent beats a relaxed-tier direct link, plan §3.4) —
    // while relaxed-tier direct links rescue every torrent-path dead end
    // below (playFirstAliveDirect), so the ladder can only ever reorder,
    // never lose the instant play the pre-ladder flow guaranteed. A direct
    // that fails validation is dropped and the selection re-runs: the next
    // pick may be another direct (instant play again) or a torrent now
    // holding the best playable tier (falls through to the probe path).
    // ignore: invalid_use_of_visible_for_testing_member
    if (SourceCandidateRanking.shouldTryDirectBeforeTorrent(rules)) {
      var selectable = torrents;
      // ignore: invalid_use_of_visible_for_testing_member
      var direct = SourceProbing.selectDirect(selectable, ladder).$1;
      while (direct != null) {
        if (cancelled()) return; // e.g. Cancel during a caller's await
        final playable = await directLooksAlive(direct);
        if (playable != null) {
          if (cancelled()) return;
          await playDirect(playable);
          return;
        }
        final dead = direct;
        selectable = selectable.where((t) => !identical(t, dead)).toList();
        // ignore: invalid_use_of_visible_for_testing_member
        direct = SourceProbing.selectDirect(selectable, ladder).$1;
      }
    }

    // Every direct link VALIDATED dead and nothing probeable exists: a
    // provider prompt (or "no provider" snack) would be nonsense — the play
    // failed because the stream links are down, say so. Budget-exhausted
    // directs are NOT in the dead set, so when unvalidated candidates remain
    // this can't fire and the trust-play rescue below still runs.
    if (deadDirectUrls.isNotEmpty &&
        !torrents.any(
          (t) => t.streamType != StreamType.externalUrl && SourceCandidateChecks.hasAcquisition(t),
        ) &&
        !torrents.any(
          (t) =>
              SourceCandidateChecks.isDirectCandidate(t) &&
              !deadDirectUrls.contains(SourceCandidateChecks.directValidationKey(t)),
        )) {
      if (ov != null) closeLoading();
      if (context.mounted) {
        SourceLoadingOverlays.snack(
          context,
          "This title's stream links appear to be offline. Open Sources to try one manually.",
        );
      }
      return;
    }

    final prov =
        provider ??
        await SourceProviderChoice.pickProvider(
          context,
          canContinue: () => context.mounted && bindingOwner.isCurrent,
        );
    // These bail-outs are reachable when the caller passed no provider (the
    // non-IMDb addon-stream path with only torrent results). Dismiss the
    // caller's overlay on each, or it stays stuck full-screen (both overlays
    // are non-dismissable by the system back button).
    if (!context.mounted || !bindingOwner.isCurrent) {
      if (ov != null) closeLoading();
      return;
    }
    if (prov == SourceProviderConfig.cancelled) {
      if (ov != null) closeLoading(); // user dismissed the picker
      return;
    }
    if (prov == null) {
      // Without a provider no torrent can play — a relaxed-tier direct link
      // is still the guaranteed instant play (pre-ladder behavior).
      if (await playFirstAliveDirect()) return;
      if (ov != null) closeLoading();
      SourceLoadingOverlays.snack(context, 'No debrid provider configured. Add one in Settings.');
      return;
    }

    var candidates = torrents
        .where(
          (t) => t.streamType != StreamType.externalUrl && SourceCandidateChecks.hasAcquisition(t),
        )
        .toList();
    if (candidates.isEmpty) {
      if (await playFirstAliveDirect()) return;
      if (ov != null) closeLoading();
      SourceLoadingOverlays.snack(context, 'No playable sources found for this title.');
      return;
    }
    // Standalone play (no loader passed by the search flow): show one now.
    ov ??= SourceLoadingOverlays.showPipeline(
      context,
      provider: prov,
      meta: meta,
      title: title ?? candidates.first.displayTitle,
    );
    final loader = ov;
    loader.setStage(PlayLoadStage.searching, sourceCount: candidates.length);
    if (prov == 'torbox' || prov == 'premiumize') {
      loader.setStage(PlayLoadStage.cacheCheck);
      candidates = await SourceCacheOrdering.cacheFirst(prov, candidates);
      // One cache call for the whole list, then a stable tier re-sort:
      // filters dominate cachedness, cached-first survives WITHIN each tier
      // (plan §3.4, "cache-first demoted to within-tier").
      if (rules != null) {
        // ignore: invalid_use_of_visible_for_testing_member
        candidates = SourceCandidateRanking.orderCacheCheckedCandidatesForRules(
          candidates,
          rules: rules,
          ladder: ladder,
        );
      } else if (tiered) {
        candidates = ladder.order(candidates);
      }
      if (!context.mounted || !bindingOwner.isCurrent) {
        // Screen went away mid cache-check — dismiss so the loader can't get
        // stuck covering the next screen.
        closeLoading();
        return;
      }
    }
    if (cancelled()) return; // user tapped Cancel during the cache-check

    // Base tier for probe narration — captured BEFORE the pack-top safety,
    // so a hoisted relaxed-tier single still triggers the tier-crossing note.
    final int probeBaseTier = tiered && candidates.isNotEmpty
        ? ladder.tierOf(candidates.first)
        : 0;
    // Pack-top safety (§3.4b.3), applied AFTER every ladder/cache re-sort so
    // no later ordering can undo it: if the ladder promoted a pack over every
    // exact-episode single, guarantee the best single still gets probed.
    var minAttempts = 1;
    if (tiered) {
      // ignore: invalid_use_of_visible_for_testing_member
      final (safeList, safeAttempts) = SourceProbing.packTopSafety(
        candidates,
        provider: prov,
        ladder: ladder,
        season: meta?.season,
        episode: meta?.episode,
      );
      candidates = safeList;
      minAttempts = safeAttempts;
    }

    loader.setStage(PlayLoadStage.preparing);
    final (res, winner) = await SourceProbing.probeCandidates(
      prov,
      candidates,
      sourceBindings: bindingOwner,
      season: meta?.season,
      episode: meta?.episode,
      rules: rules,
      isCancelled: cancelled,
      minAttempts: minAttempts,
      onCandidate: !tiered
          ? null
          : (t) {
              // Narrate tier crossings while probing (try-multiple / the
              // pack-top safety attempt).
              final tier = ladder.tierOf(t);
              if (tier > probeBaseTier) {
                loader.setNote(
                  "Filtered match wasn't playable — trying "
                  '${ladder.describeTier(tier) ?? 'any available source'}',
                );
              }
            },
    );
    if (cancelled()) return; // dismissed by the Cancel tap; nothing more to do
    loader.setStage(PlayLoadStage.starting);
    if (!context.mounted || !bindingOwner.isCurrent) {
      closeLoading();
      return;
    }
    if (res == null) {
      // Every probe failed — a ladder-demoted direct link still guarantees
      // the play the pre-ladder flow would have delivered (playDirect keeps
      // the loader up and hands its dismissal to the launcher).
      if (await playFirstAliveDirect()) return;
      closeLoading();
      SourceLoadingOverlays.snack(
        context,
        'No instantly-playable source found. Open Sources to pick or download one.',
      );
      return;
    }
    final idx = torrents.indexOf(winner!);
    await SourcePlayerLaunch.launch(
      context,
      res,
      winner.displayTitle,
      provider: prov,
      meta: meta,
      sources: torrents,
      sourceIndex: idx < 0 ? 0 : idx,
      seriesFetcher: seriesFetcher,
      overlay: loader,
      startupFailoverEnabled: true,

      sourceBindings: bindingOwner,
    );
  }

  /// Full catalog-play flow: pick provider, show the cinematic overlay (with the
  /// real provider name), search torrents for the title, and auto-play the best
  /// — all under ONE overlay. Used by the Search tab's catalog Play button.
  // TEMP(tps): moves in step 4
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
  }) async {
    final bindingOwner = sourceBindings ?? AutomaticSourceBindings.capture();
    if (!context.mounted || !bindingOwner.isCurrent) return;
    logSourceSelection(
      'play_selection_start',
      season: season,
      episode: episode,
      reason: skipBoundSources
          ? 'recovery_skip_saved'
          : 'saved_then_quick_play',
    );
    final label = meta.title ?? '';
    if (imdbId.isEmpty) {
      SourceLoadingOverlays.snack(context, 'No IMDb match to find sources for "$label".');
      return;
    }
    var cancelled = false;
    final resolving = SourceLoadingOverlays.showResolvingOverlay(
      context,
      meta: meta,
      title: label,
      onCancel: () => cancelled = true,
    );
    late final QuickPlayRules rules;
    // 'quick' (the default) leaves every path below exactly as it shipped. Read
    // under the overlay, next to the rules, so the default path's time-to-overlay
    // is unchanged.
    var playMode = 'quick';
    try {
      rules = await StorageService.getQuickPlayRules(isMovie: isMovie);
      if (openSourcePicker != null) {
        playMode = await StorageService.getPlayButtonMode();
      }
      if (rules.sourcePriority.isNotEmpty) await SourceCandidateRanking.warmSourceAliases();
    } catch (_) {
      resolving.dismiss();
      rethrow;
    }
    // "Always ask" wants the list regardless of what is pinned, so it enters
    // below the binding gate the same way failure-recovery does.
    final skipBound = skipBoundSources || playMode == 'always';
    // True when this press has been handed to the manual source list and the
    // caller must stop. Reads the callback through a local so neither hand-off
    // site needs a `!`, which would be a latent trap if [playMode] ever gained
    // another writer.
    final opener = openSourcePicker;
    bool handedToPicker() {
      if (playMode == 'quick' || opener == null) return false;
      // The last link in the [SeriesResume] chain: whatever episode arrives
      // here is the one the manual list opens on. Compare against the
      // `play-launch` line — if they differ, the selection was rebuilt between
      // the two; if they agree but disagree with `label-resolve-result`, the
      // label and the press reconciled to different answers.
      debugPrint(
        '[SeriesResume] picker-handoff title="$label" mode=$playMode '
        'target=S${season}E$episode metaTarget=S${meta.season}E${meta.episode}',
      );
      resolving.dismiss();
      if (context.mounted && !cancelled) opener();
      return true;
    }

    var activeRules = rules;
    if ((!context.mounted || !bindingOwner.isCurrent) || cancelled) {
      resolving.dismiss();
      return;
    }

    // Any non-`tt` id can't be resolved by the torrent engines — they key on
    // `tt…` ids — so addon-enabled profiles resolve these through the addon's
    // own /stream endpoint. This covers IPTV/TV channels AND kitsu/tmdb-only
    // movie & series catalogs, and matches old home, whose quick-play always ran
    // the Stremio-inclusive search. An explicit torrents-only profile fails
    // clearly instead of silently querying addons. A `tt…` id — even a
    // non-standard type like some anime catalogs — keeps the normal torrent
    // search below so the on-device engines still run. (imdbId.isEmpty is
    // already handled above.)
    if (!imdbId.startsWith('tt')) {
      // ignore: invalid_use_of_visible_for_testing_member
      if (!SourceSearchPlans.allowsAddonSearch(rules)) {
        resolving.dismiss();
        SourceLoadingOverlays.snack(
          context,
          'Torrent engines can’t search "$label" without an IMDb ID. Choose a source mode that allows addons.',
        );
        return;
      }
      // Kitsu/tmdb-only catalogs are a real slice of the library, so the picker
      // modes have to apply here too — otherwise "Always show sources" silently
      // does nothing for anime. The manual list handles a non-`tt` id fine: it
      // passes the id straight to searchByImdbWithStremio, whose addon half
      // accepts it (the engine half just returns nothing). Handing over BEFORE
      // the addon auto-play costs no pinned-source reuse — this branch already
      // returns above the binding gate, so non-`tt` ids never had any. The
      // torrents-only guard stays ahead of this: an empty picker would be a
      // worse answer than the explicit message.
      if (handedToPicker()) return;
      resolving.dismiss();
      await playAddonStream(
        context,
        imdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
        meta: meta,
        label: label,
        rules: rules,
        forceAddonOnly: true,

        sourceBindings: bindingOwner,
      );
      return;
    }

    // Bound-source reuse: if the user pinned a source for this title, play it
    // directly and skip the torrent search entirely. A series binding is only
    // usable when a concrete season+episode is requested (to land in the pack).
    if (!skipBound) {
      late final List<SeriesSource> bound;
      try {
        bound = (await SeriesSourceService.getSources(
          imdbId,
        )).where((source) => SourceCandidateChecks.bindingMatchesMeta(source, meta)).toList();
      } catch (_) {
        resolving.dismiss();
        rethrow;
      }
      if ((!context.mounted || !bindingOwner.isCurrent) || cancelled) {
        resolving.dismiss();
        return;
      }
      // A series binding needs a concrete season+episode to land inside the
      // pack. Gate on the same fields _launch forwards to the player (meta.*),
      // so the requested episode reaches the existing exact-episode checks.
      final boundUsable =
          bound.isNotEmpty &&
          (isMovie || (meta.season != null && meta.episode != null));
      if (boundUsable) {
        resolving.dismiss();
        final played = await playViaBound(
          context,
          imdbId,
          bound,
          label: label,
          meta: meta,
          preferredProvider: preferredProvider,

          sourceBindings: bindingOwner,
        );
        if (played) return;
        if (!context.mounted || !bindingOwner.isCurrent) return;
        // Bound source unplayable → fall through to a normal search below.
      }
    }

    // Everything above this line is the pinned-source contract; everything below
    // it auto-picks. Both non-default modes stop here and hand the user the list
    // instead — reaching this point already means "no pinned source played",
    // whether because none was pinned, the pin didn't cover this episode, or the
    // pin was dead. That makes the branch correct by construction: it needs no
    // separate notion of pin eligibility, which a title-level count could not
    // have answered for a series pinned only as single episodes.
    if (handedToPicker()) return;

    // A custom Stremio episode ID describes content that IMDb torrent/IPTV
    // sources cannot safely substitute (for example, a fan edit). Query its
    // protocol ID directly before provider selection, regardless of the
    // ordinary torrent-vs-addon preference for canonical titles.
    if (meta.hasStremioEpisodeIdentity) {
      resolving.dismiss();
      await playAddonStream(
        context,
        imdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
        meta: meta,
        label: label,
        rules: rules,
        forceAddonOnly: true,

        sourceBindings: bindingOwner,
      );
      return;
    }

    // Addon-leading, exact-episode routes search addons before asking the user
    // to choose a debrid provider. Direct addon links need no provider at all;
    // addon torrents still trigger the picker lazily inside playBest. Series
    // pack-first routes keep their existing provider-first contract because a
    // reusable torrent pack must be cache-probed before an episode fallback.
    var addonFallbackAlreadySearched = false;
    // ignore: invalid_use_of_visible_for_testing_member
    if (SourceSearchPlans.shouldSearchAddonsBeforeProvider(
      rules,
      isMovie: isMovie,
      hasPreferredProvider: preferredProvider != null,
    )) {
      resolving.dismiss();
      final fallBackToEngines =
          rules.sourceMode == QuickPlaySourceMode.addonsThenTorrents;
      final handled = await playAddonStream(
        context,
        imdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
        meta: meta,
        label: label,
        rules: rules,
        forceAddonOnly: true,
        fallbackWhenEmpty: fallBackToEngines,

        sourceBindings: bindingOwner,
      );
      if ((!context.mounted || !bindingOwner.isCurrent) || handled) return;
      addonFallbackAlreadySearched = true;
      // The addon stage has already completed empty. Continue with only the
      // engine half instead of querying the same addons a second time.
      activeRules = rules.copyWith(
        sourceMode: QuickPlaySourceMode.torrentsOnly,
        preserveLegacyCombinedPackSearch: false,
      );
    }

    resolving.dismiss();
    final provider =
        preferredProvider ??
        await SourceProviderChoice.pickProvider(
          context,
          canContinue: () => context.mounted && bindingOwner.isCurrent,
        );
    if (!context.mounted || !bindingOwner.isCurrent) return;
    if (provider == SourceProviderConfig.cancelled) return;
    if (provider == null) {
      if (addonFallbackAlreadySearched) {
        SourceLoadingOverlays.snack(
          context,
          'No direct stream for "$label". Add a debrid provider in Settings for more sources.',
        );
        return;
      }
      // ignore: invalid_use_of_visible_for_testing_member
      if (!SourceSearchPlans.allowsAddonSearch(activeRules)) {
        SourceLoadingOverlays.snack(
          context,
          'No debrid provider configured. Add one in Settings to use torrent-only Quick Play.',
        );
        return;
      }
      // No debrid provider — but some titles still have a direct addon stream
      // that plays without one. Run an addon-only search and let playBest open
      // a direct link; if there's none it shows the "add a provider" snack.
      await playAddonStream(
        context,
        imdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
        meta: meta,
        label: label,
        noProvider: true,
        rules: activeRules,

        sourceBindings: bindingOwner,
      );
      return;
    }
    // The Pipeline loader spans search → cache-check → prepare → start; its
    // checklist advances via setStage as this flow progresses.
    final cancel = PlaybackCancelToken();
    final overlay = SourceLoadingOverlays.showPipeline(
      context,
      provider: provider,
      meta: meta,
      title: label,
      onCancel: () => cancel.cancelled = true,
    );
    void closeLoading() => overlay.dismiss();

    // Quick-play filter ladder: saved default filters as a tiered preference
    // (full match → relax language → relax rip → anything). Inactive when no
    // filters are set or the Filter Settings toggle is off — then every
    // ladder call below is a no-op and behavior is unchanged. Size buckets are
    // movie-only (pack sizes are per-episode), so they're stripped for series.
    final ladder = await SourceFilterLadder.loadLadder(includeSize: isMovie, rules: activeRules);
    if (cancel.cancelled) return; // Cancel during the prefs read
    if (!context.mounted || !bindingOwner.isCurrent) {
      closeLoading();
      return;
    }

    // Series auto-pin (on by default, toggle in Quick Play settings): with no
    // usable pinned source, search PACKS
    // first — the whole-series search with season probing, same as the
    // Sources screen's "Show Season Packs" — and play the widest pack that
    // actually contains the requested episode (complete series → multi-season
    // → season pack). _launch's auto-bind then pins the winner, so every later
    // play of this series goes straight through the bound path. When no pack
    // qualifies or none is instantly playable, fall through to the normal
    // episode search below (whose winner also gets pinned).
    // PikPak is excluded: it has no cache check, so each pack probe queues a
    // real (large) offline download to the user's account that can't be
    // cheaply cleaned up — pack-first there would be actively harmful.
    // The series pack route, shared by pack-FIRST (preferSeriesPacks on) and
    // pack-FALLBACK (off, episode search found nothing). Returns true when a
    // pack launched, false to continue, null when the flow must stop
    // (cancelled / unmounted).
    Future<bool?> tryPackRoute() async {
      // null = the SEARCH failed (transient network) — the episode search
      // still runs, and we DON'T poison the negative cache so the next
      // episode retries rather than deferring for the whole TTL.
      final packResult = await SeriesPackSearch.searchSeriesPackSources(
        imdbId: imdbId,
        label: label,
        season: season!,
        provider: provider,
        ladder: ladder,
        rules: activeRules,
        isCancelled: () =>
            cancel.cancelled || !context.mounted || !bindingOwner.isCurrent,
        onCacheCheck: () => overlay.setStage(PlayLoadStage.cacheCheck),
      );
      final searchOk = packResult != null;
      final packs = packResult ?? const <Torrent>[];
      if (cancel.cancelled) return null;
      if (!context.mounted || !bindingOwner.isCurrent) {
        closeLoading();
        return null;
      }
      SourceLoadingOverlays.applyLadderNote(overlay, ladder, packs);
      if (cancel.cancelled) return null;
      if (!context.mounted || !bindingOwner.isCurrent) {
        closeLoading();
        return null;
      }
      if (packs.isNotEmpty) {
        overlay.setStage(PlayLoadStage.preparing);
        final (packResolved, packWinner) = await SourceProbing.probeCandidates(
          provider,
          packs,
          sourceBindings: bindingOwner,
          season: season,
          episode: episode,
          rules: activeRules,
          isCancelled: () =>
              cancel.cancelled || !context.mounted || !bindingOwner.isCurrent,
        );
        if (cancel.cancelled) return null;
        if (!context.mounted || !bindingOwner.isCurrent) {
          closeLoading();
          return null;
        }
        if (packResolved != null && packWinner != null) {
          overlay.setStage(PlayLoadStage.starting);
          // No closeLoading here: the loader stays up through the launch prep
          // and _launch has it dismissed when the player takes the screen.
          final idx = packs.indexOf(packWinner);
          await SourcePlayerLaunch.launch(
            context,
            packResolved,
            packWinner.displayTitle,
            provider: provider,
            meta: meta,
            sources: packs,
            sourceIndex: idx < 0 ? 0 : idx,
            seriesFetcher: SourceSeriesFetcher.seriesFetcherFor(
              meta: meta,
              provider: provider,
              packsFetched: true,
            ),
            overlay: overlay,
            startupFailoverEnabled: true,

            sourceBindings: bindingOwner,
          );
          return true;
        }
        // No pack was instantly playable — fall through to the episode search.
      }
      // Reached only when no pack played (cancel / unmount paths returned
      // above). Remember it — but only when the search actually SUCCEEDED with
      // no playable pack (not a transient failure) — so the next episode of
      // this season skips the pack search until the TTL lapses.
      if (searchOk) {
        _markNoPack(
          imdbId,
          season,
          provider,
          activeRules,
          Duration(hours: activeRules.failedPackCacheHours),
        );
      }
      return false;
    }

    final packRouteAllowed =
        !isMovie &&
        !meta.hasStremioEpisodeIdentity &&
        season != null &&
        episode != null &&
        provider != 'pikpak' &&
        !_recentlyNoPack(imdbId, season, provider, activeRules) &&
        activeRules.packPreference != QuickPlayPackPreference.exactEpisodeOnly;

    final iptvFirst =
        activeRules.allowDirectLinks &&
        // ignore: invalid_use_of_visible_for_testing_member
        SourceSearchPlans.allowsAddonSearch(activeRules) &&
        activeRules.sourcePriority.isNotEmpty &&
        activeRules.sourcePriority.first.startsWith('iptv:');
    if (packRouteAllowed && activeRules.preferSeriesPacks) {
      if (iptvFirst) {
        final prioritizedPlaylistId = activeRules.sourcePriority.first
            .substring('iptv:'.length);
        logIptvSourceEvent(
          'quick_play_priority_probe_started',
          playlistId: prioritizedPlaylistId,
          catalogType: 'series',
          season: season,
          episode: episode,
        );
        // ignore: invalid_use_of_visible_for_testing_member
        final matches = await IptvQuickPlaySearch.searchIptvForQuickPlay(
          imdbId,
          meta.title ?? label,
          meta.year,
          isMovie,
          season,
          episode,
          activeRules,
          () => cancel.cancelled,
        );
        final prioritized = SourceCandidateRanking.orderCandidatesForRules(
          matches
              .where((t) => t.source == activeRules.sourcePriority.first)
              .toList(),
          rules: activeRules,
          ladder: ladder,
        );
        logIptvSourceEvent(
          'quick_play_priority_probe_candidates',
          playlistId: prioritizedPlaylistId,
          catalogType: 'series',
          season: season,
          episode: episode,
          resultCount: prioritized.length,
          outcome: prioritized.isEmpty ? 'no_match' : 'matched',
        );
        final iptvPriorityDeadline = DateTime.now().add(
          SourceIptvAvailability.iptvQuickPlaySearchTimeout,
        );
        for (final descriptor in prioritized.take(
          SourceCandidateRanking.directValidationBudgetForRules(activeRules),
        )) {
          if (cancel.cancelled ||
              (!context.mounted || !bindingOwner.isCurrent)) {
            return;
          }
          try {
            var source = descriptor;
            if (IptvSourceSearch.isDeferredXtreamSeries(source)) {
              final remaining = iptvPriorityDeadline.difference(DateTime.now());
              if (remaining <= Duration.zero) break;
              final resolution =
                  await IptvSourceSearch.resolveXtreamSeriesEpisode(
                    source,
                    season: season,
                    episode: episode,
                  ).timeout(
                    remaining,
                    onTimeout: () => const IptvEpisodeResolution(
                      IptvEpisodeResolutionStatus.unavailable,
                    ),
                  );
              if (resolution.source == null) continue;
              source = resolution.source!;
            }
            await DirectSourceAuthorization.authorize(source);
            final alive =
                !activeRules.validateDirectLinks ||
                !SourceCandidateRanking.shouldPreflightDirectStream(source) ||
                await StreamUrlValidator.isPlayableVideoUrl(
                  source.directUrl!,
                  minBytes: 10 * 1024 * 1024,
                  lenient: true,
                  headers: source.httpHeaders,
                );
            if (!alive) {
              logIptvSourceEvent(
                'quick_play_candidate_rejected',
                source: source,
                stage: 'preflight',
                outcome: 'unplayable',
                season: season,
                episode: episode,
              );
              continue;
            }
            if (cancel.cancelled ||
                (!context.mounted || !bindingOwner.isCurrent)) {
              return;
            }
            logIptvSourceEvent(
              'quick_play_candidate_selected',
              source: source,
              outcome: 'priority_winner',
              season: season,
              episode: episode,
            );
            await playBest(
              context,
              [source],
              provider: provider,
              title: label,
              meta: meta,
              overlay: overlay,
              isCancelled: () =>
                  cancel.cancelled ||
                  !context.mounted ||
                  !bindingOwner.isCurrent,
              ladder: ladder,
              rules: activeRules.copyWith(validateDirectLinks: false),
              seriesFetcher: SourceSeriesFetcher.seriesFetcherFor(meta: meta, provider: provider),

              sourceBindings: bindingOwner,
            );
            return;
          } catch (error) {
            // Revoked or unusable IPTV must not disable the preferred pack route.
            logIptvSourceEvent(
              'quick_play_candidate_rejected',
              source: descriptor,
              stage: 'authorization_or_probe',
              outcome: 'failed',
              season: season,
              episode: episode,
              error: error,
            );
          }
        }
      }
      if (cancel.cancelled || (!context.mounted || !bindingOwner.isCurrent)) {
        return;
      }
      final packed = await tryPackRoute();
      if (packed != false) return;
    }

    List<Torrent> torrents;
    try {
      torrents = await CuratedSourceSearch.searchCuratedSources(
        imdbId: imdbId,
        label: label,
        year: meta.year,
        isMovie: isMovie,
        season: season,
        episode: episode,
        provider: provider,
        rules: activeRules,
        originMeta: meta,
        isCancelled: () =>
            cancel.cancelled || !context.mounted || !bindingOwner.isCurrent,
        onResults: (n) =>
            overlay.setStage(PlayLoadStage.searching, sourceCount: n),
      );
    } catch (e) {
      if (cancel.cancelled) return; // overlay already dismissed by Cancel
      closeLoading();
      if (context.mounted) SourceLoadingOverlays.snack(context, 'Search failed: $e');
      return;
    }
    if (cancel.cancelled) return;
    if (!context.mounted || !bindingOwner.isCurrent) {
      closeLoading();
      return;
    }
    // Apply the same Addon Priority/filter ordering that [playBest] will use
    // before probing lazy IPTV rows. Otherwise catalog order can make a slow
    // lower-priority playlist consume the deadline ahead of the user's first
    // choice.
    torrents = SourceCandidateRanking.orderCandidatesForRules(
      torrents,
      rules: activeRules,
      ladder: ladder,
    );
    if (packRouteAllowed &&
        !activeRules.preferSeriesPacks &&
        torrents.any(IptvSourceSearch.isDeferredXtreamSeries)) {
      // ignore: invalid_use_of_visible_for_testing_member
      torrents = await SourceIptvAvailability.confirmDeferredIptvAvailability(
        torrents,
        season: season,
        episode: episode,
        isCancelled: () =>
            cancel.cancelled || !context.mounted || !bindingOwner.isCurrent,
      );
      if (cancel.cancelled) return;
      if (!context.mounted || !bindingOwner.isCurrent) {
        closeLoading();
        return;
      }
    }
    // ignore: invalid_use_of_visible_for_testing_member
    if (!torrents.any(SourceCandidateRanking.isAutoPlayableCandidate)) {
      // Episode-first route (Prefer season packs off): packs are the
      // FALLBACK when the episode search comes up dry, so a show that only
      // exists as packs still plays. Deferred IPTV title matches count only
      // after one of them resolves the requested episode.
      if (packRouteAllowed && !activeRules.preferSeriesPacks) {
        final packed = await tryPackRoute();
        if (packed != false) return;
      }
      closeLoading();
      SourceLoadingOverlays.snack(context, 'No sources found for "$label".');
      return;
    }

    // The list was ranked before lazy IPTV probing so the fallback gate and
    // automatic playback agree on which provider comes first. [playBest]
    // performs its own final defensive ordering before selection.
    if (torrents.isEmpty) {
      closeLoading();
      SourceLoadingOverlays.snack(context, 'No sources match your Quick Play rules for "$label".');
      return;
    }
    SourceLoadingOverlays.applyLadderNote(overlay, ladder, torrents);
    await playBest(
      context,
      torrents,
      provider: provider,
      title: label,
      meta: meta,
      overlay: overlay,
      isCancelled: () =>
          cancel.cancelled || !context.mounted || !bindingOwner.isCurrent,
      ladder: ladder,
      rules: activeRules,
      // The dedicated episode fetch just ran; the pack tab stays fetchable
      // even when the pack-first search ran earlier — its results were
      // discarded (nothing instantly playable), so "Load more" re-lists
      // them for a manual pick.
      seriesFetcher: SourceSeriesFetcher.seriesFetcherFor(
        meta: meta,
        provider: provider,
        episodesFetched: true,
      ),

      sourceBindings: bindingOwner,
    );
  }

  // TEMP(tps): moves in step 4
  static Future<bool> playAddonStream(
    BuildContext context,
    String id, {
    required bool isMovie,
    int? season,
    int? episode,
    required PlaybackMeta meta,
    required String label,
    required QuickPlayRules rules,
    // No-provider fast path: a `tt` title with no debrid configured. Search
    // addons ONLY (skip the torrent engines whose results couldn't play
    // anyway), and when nothing turns up point the user at Settings instead of
    // the generic "no stream" message — adding a provider is the real fix.
    bool noProvider = false,
    // Used by addon-leading profiles before a provider is selected. It keeps
    // this pass strictly on addons; when empty, addons-then-engines can dismiss
    // the neutral loader and continue into its engine fallback.
    bool forceAddonOnly = false,
    bool fallbackWhenEmpty = false,
    required AutomaticSourceBindings sourceBindings,
  }) async {
    final cancel = PlaybackCancelToken();
    // Direct addon/IPTV stream — the loader dismisses as soon as playBest opens
    // the direct stream. Neutral "Stream" identity (no debrid provider).
    final overlay = SourceLoadingOverlays.showPipeline(
      context,
      provider: 'stream',
      meta: meta,
      title: label,
      onCancel: () => cancel.cancelled = true,
    );
    void closeLoading() => overlay.dismiss();

    final addonTimeout = rules.addonTimeoutSeconds == 15
        ? null
        : Duration(seconds: rules.addonTimeoutSeconds);
    final engineTimeout = rules.searchTimeoutSeconds == 0
        ? null
        : Duration(seconds: rules.searchTimeoutSeconds);
    final exactAddonOrder = rules.ranking == QuickPlayRanking.exactOrder;
    final originVideoId = await CuratedSourceSearch.originEpisodeVideoId(meta, season, episode);
    if (meta.hasStremioEpisodeIdentity && originVideoId == null) {
      closeLoading();
      if (context.mounted) {
        SourceLoadingOverlays.snack(context, 'This episode is not available from its catalog.');
      }
      return true;
    }
    final earlyScope = ProfileRuntime.scope.value;
    final early = Completer<Map<String, dynamic>>();
    final earlyLadder = await SourceFilterLadder.loadLadder(includeSize: isMovie, rules: rules);
    String? leadingAddon;
    // An exact-order addon-only pass can decide as soon as its FIRST provider
    // answers. Global-quality and torrent-preferred searches need all results.
    if (!isMovie &&
        !meta.hasStremioEpisodeIdentity &&
        id.startsWith('tt') &&
        season != null &&
        episode != null &&
        rules.allowDirectLinks &&
        rules.tryNextOnFailure &&
        exactAddonOrder &&
        // ignore: invalid_use_of_visible_for_testing_member
        !SourceCandidateRanking.prefersTorrentCandidates(rules) &&
        (noProvider ||
            forceAddonOnly ||
            rules.sourceMode == QuickPlaySourceMode.addonsOnly)) {
      try {
        final addons = await StremioService.instance.applicableStreamingAddons(
          type: 'series',
          contentId: id,
        );
        // ignore: invalid_use_of_visible_for_testing_member
        leadingAddon = SourceCuration.leadingDirectAddonKey(addons, rules.sourcePriority);
      } catch (_) {
        // Optional fast path: ordinary search still owns errors/retries.
      }
    }
    if (cancel.cancelled || (!context.mounted || !sourceBindings.isCurrent)) {
      closeLoading();
      return true;
    }
    void onDirectBatch(String source, List<Torrent> batch) {
      if (source != leadingAddon || early.isCompleted || cancel.cancelled)
        return;
      if (ProfileRuntime.scope.value != earlyScope) return;
      // ignore: invalid_use_of_visible_for_testing_member
      final selected = SourceCuration.earlyDirectCandidate(
        batch,
        rules: rules,
        ladder: earlyLadder,
      );
      if (selected == null) return;
      early.complete({
        'torrents': [selected],
        'earlyDirect': true,
      });
    }

    Future<Map<String, dynamic>> query(QuickPlaySourceMode stage) {
      switch (stage) {
        case QuickPlaySourceMode.addonsOnly:
          return TorrentService.searchStremioAddonsOnly(
            imdbId: id,
            isMovie: isMovie,
            season: season,
            episode: episode,
            contentType: meta.contentType,
            timeout: addonTimeout,
            preserveOrder: exactAddonOrder,
            onBatch: leadingAddon == null ? null : onDirectBatch,
            originAddonKey: meta.stremioAddonKey,
            originVideoId: originVideoId,
          );
        case QuickPlaySourceMode.torrentsOnly:
          return TorrentService.searchByImdb(
            id,
            isMovie: isMovie,
            season: season,
            episode: episode,
            timeout: engineTimeout,
            preserveSourceOrder: exactAddonOrder,
          );
        case QuickPlaySourceMode.together:
          return TorrentService.searchByImdbWithStremio(
            id,
            isMovie: isMovie,
            season: season,
            episode: episode,
            contentType: meta.contentType,
            engineTimeout: engineTimeout,
            stremioTimeout: addonTimeout,
            preserveSourceOrder: exactAddonOrder,
            originAddonKey: meta.stremioAddonKey,
            originVideoId: originVideoId,
          );
        case QuickPlaySourceMode.torrentsThenAddons:
        case QuickPlaySourceMode.addonsThenTorrents:
          throw StateError('Fallback source modes must be expanded first');
      }
    }

    Future<Map<String, dynamic>> search() async {
      final iptv = meta.hasStremioEpisodeIdentity
          ? Future.value(const <Torrent>[])
          // ignore: invalid_use_of_visible_for_testing_member
          : IptvQuickPlaySearch.searchIptvForQuickPlay(
              id,
              meta.title ?? label,
              meta.year,
              isMovie,
              season,
              episode,
              rules,
              () => cancel.cancelled,
            );
      final torrents = <Torrent>[];
      final engineErrors = <String, String>{};
      final addonErrors = <String, String>{};
      final addonStatuses = <AddonSearchStatus>[];
      final stages = meta.hasStremioEpisodeIdentity
          ? const [QuickPlaySourceMode.addonsOnly]
          // ignore: invalid_use_of_visible_for_testing_member
          : SourceSearchPlans.addonStreamSearchPlan(
              rules,
              noProvider: noProvider,
              forceAddonOnly: forceAddonOnly,
            );
      for (final stage in stages) {
        final result = await query(stage);
        final stageTorrents = (result['torrents'] as List).cast<Torrent>();
        torrents.addAll(stageTorrents);
        engineErrors.addAll(
          (result['engineErrors'] as Map?)?.cast<String, String>() ?? const {},
        );
        addonErrors.addAll(
          (result['addonErrors'] as Map?)?.cast<String, String>() ?? const {},
        );
        addonStatuses.addAll(
          (result['addonStatuses'] as List?)?.cast<AddonSearchStatus>() ??
              const [],
        );
        // Forced/no-provider searches are addon-only; mixed provider searches
        // are a single combined stage. Keep this guard for explicit one-stage
        // legacy modes and to avoid unnecessary future stages if added.
        final foundUsable = stageTorrents.any(
          (torrent) =>
              (rules.allowDirectLinks ||
                  torrent.streamType != StreamType.directUrl) &&
              // ignore: invalid_use_of_visible_for_testing_member
              SourceCandidateRanking.isAutoPlayableCandidate(torrent),
        );
        if (foundUsable) break;
      }
      return {
        'torrents': [...torrents, ...await iptv],
        'engineErrors': engineErrors,
        'addonErrors': addonErrors,
        'addonStatuses': addonStatuses,
      };
    }

    Map<String, dynamic> res;
    final fullSearch = search();
    try {
      res = await Future.any([fullSearch, early.future]);
    } catch (e) {
      if (cancel.cancelled) return true;
      closeLoading();
      if (fallbackWhenEmpty) return false;
      if (context.mounted) SourceLoadingOverlays.snack(context, 'Search failed: $e');
      return true;
    }
    if (res['earlyDirect'] == true) {
      final selected = (res['torrents'] as List<Torrent>).single;
      final alive =
          !rules.validateDirectLinks ||
          SourceCandidateRanking.directValidationBudgetForRules(rules) <= 0 ||
          !SourceCandidateRanking.shouldPreflightDirectStream(selected) ||
          await StreamUrlValidator.isPlayableVideoUrl(
            selected.directUrl!,
            minBytes: 10 * 1024 * 1024,
            lenient: true,
            headers: selected.httpHeaders,
          );
      if (cancel.cancelled ||
          (!context.mounted || !sourceBindings.isCurrent) ||
          ProfileRuntime.scope.value != earlyScope) {
        closeLoading();
        return true;
      }
      if (alive) {
        final remaining = fullSearch.then(
          (result) => SourceCandidateRanking.orderCandidatesForRules(
            (result['torrents'] as List).cast<Torrent>(),
            rules: rules,
            ladder: earlyLadder,
          ),
          onError: (Object _, StackTrace __) => <Torrent>[],
        );
        final fetcher = SourceSeriesFetcher.seriesFetcherFor(
          meta: meta,
          initialEpisodeSearch: remaining,
        );
        await SourcePlayerLaunch.launch(
          context,
          ResolvedSource(
            title: selected.displayTitle,
            playUrl: selected.directUrl,
            httpHeaders: selected.httpHeaders,
          ),
          selected.displayTitle,
          provider: SeriesSource.addonDirectService,
          meta: meta,
          sources: [selected],
          seriesFetcher: fetcher,
          overlay: overlay,
          startupFailoverEnabled: true,
          onStartupSourcesExhausted: () async {
            // ignore: invalid_use_of_visible_for_testing_member
            final recovery = SourceCuration.earlyDirectRecovery(
              await remaining,
              failed: selected,
              rules: rules,
            );
            if ((!context.mounted || !sourceBindings.isCurrent) ||
                cancel.cancelled ||
                ProfileRuntime.scope.value != earlyScope)
              return;
            await playBest(
              context,
              recovery.sources,
              title: label,
              meta: meta,
              rules: recovery.rules,
              ladder: earlyLadder,
              seriesFetcher: fetcher,

              sourceBindings: sourceBindings,
            );
          },

          sourceBindings: sourceBindings,
        );
        return true;
      }
      // The early candidate failed preflight. Keep the normal complete-search
      // failure/retry path rather than discarding slower addon results.
      res = await fullSearch;
      res = {
        ...res,
        'torrents': (res['torrents'] as List)
            .cast<Torrent>()
            .where(
              (t) => SourceCandidateChecks.directValidationKey(t) != SourceCandidateChecks.directValidationKey(selected),
            )
            .toList(),
      };
    }
    if (cancel.cancelled) return true;
    if (!context.mounted || !sourceBindings.isCurrent) {
      closeLoading();
      return true;
    }
    // Addon errors ride along keyed by configuration-specific source id
    // (timeouts and upstream 5xx land here, not as a thrown exception). The
    // two searches
    // surface them under different keys: searchByImdbWithStremio folds addon +
    // engine errors together under 'engineErrors', while the noProvider path's
    // searchStremioAddonsOnly returns them raw under 'addonErrors'. Read both,
    // then keep only direct-provider keys — a flaky engine must not misblame
    // "didn't respond" on a title that simply has no stream.
    String failedAddonNamesOf(
      Map<String, dynamic> r,
      Map<String, String> errors,
    ) {
      final statuses =
          r['addonStatuses'] as List<AddonSearchStatus>? ?? const [];
      final names = <String>[
        for (final status in statuses)
          if (errors.containsKey(status.sourceKey)) status.name,
      ];
      if (names.isNotEmpty) return names.join(', ');
      return errors.keys
          .map((key) => key.replaceFirst('stremio:', ''))
          .join(', ');
    }

    var torrents = (res['torrents'] as List).cast<Torrent>();
    // ignore: invalid_use_of_visible_for_testing_member
    var errors = SourceCuration.directSearchErrors(res);
    // Empty ONLY because an addon errored is usually a transient upstream
    // blip — retry once before giving up.
    if (torrents.isEmpty && errors.isNotEmpty) {
      try {
        res = await search();
        torrents = (res['torrents'] as List).cast<Torrent>();
        // ignore: invalid_use_of_visible_for_testing_member
        errors = SourceCuration.directSearchErrors(res);
      } catch (_) {
        // Keep the first attempt's (empty) result — reported below.
      }
      if (cancel.cancelled) return true;
      if (!context.mounted || !sourceBindings.isCurrent) {
        closeLoading();
        return true;
      }
    }
    if (torrents.isEmpty) {
      closeLoading();
      if (fallbackWhenEmpty) return false;
      // An errored addon means "didn't respond", not "has no stream" — say
      // so, since a retry will usually succeed.
      if (errors.isNotEmpty) {
        final failed = failedAddonNamesOf(res, errors);
        final nativeErrors = errors.entries
            .where((entry) => entry.key.startsWith('mediaserver:'))
            .map((entry) => entry.value)
            .toSet();
        SourceLoadingOverlays.snack(
          context,
          nativeErrors.isEmpty
              ? '$failed didn\'t respond for "$label" — try again.'
              : '$failed: ${nativeErrors.join(' ')}',
        );
      } else {
        // noProvider: addons searched fine and returned nothing directly
        // playable. Torrent engines were skipped (they need a provider), so the
        // actionable next step is to add one — but don't claim the title has no
        // stream at all, only that none plays without a provider.
        SourceLoadingOverlays.snack(
          context,
          noProvider
              ? 'No direct stream for "$label". Add a debrid provider in Settings for more sources.'
              : 'No stream found for "$label".',
        );
      }
      return true;
    }
    // Reuse the same preference snapshot used for the early candidate.
    final ladder = earlyLadder;
    if (cancel.cancelled) return true; // Cancel during the prefs read
    if (!context.mounted || !sourceBindings.isCurrent) {
      closeLoading();
      return true;
    }
    torrents = SourceCandidateRanking.orderCandidatesForRules(torrents, rules: rules, ladder: ladder);
    if (fallbackWhenEmpty) {
      // ignore: invalid_use_of_visible_for_testing_member
      torrents = await SourceIptvAvailability.confirmDeferredIptvAvailability(
        torrents,
        season: season,
        episode: episode,
        isCancelled: () => cancel.cancelled,
      );
      if (cancel.cancelled) return true;
      if (!context.mounted || !sourceBindings.isCurrent) {
        closeLoading();
        return true;
      }
      // ignore: invalid_use_of_visible_for_testing_member
      if (!torrents.any(SourceCandidateRanking.isAutoPlayableCandidate)) {
        closeLoading();
        return false;
      }
    }
    SourceLoadingOverlays.applyLadderNote(overlay, ladder, torrents);
    // playBest plays a direct addon stream instantly (no provider needed); if
    // there somehow isn't one it falls through to the normal provider path.
    await playBest(
      context,
      torrents,
      title: label,
      meta: meta,
      overlay: overlay,
      isCancelled: () => cancel.cancelled,
      ladder: ladder,
      rules: rules,
      seriesFetcher: isMovie
          ? SourceMovieFetcher.movieFetcherFor(meta: meta)
          : SourceSeriesFetcher.seriesFetcherFor(meta: meta, episodesFetched: true),

      sourceBindings: sourceBindings,
    );
    return true;
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
