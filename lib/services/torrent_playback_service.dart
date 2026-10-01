import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../features/sources/data/automatic_source_bindings.dart';
import '../features/sources/data/manual_source_preparation.dart';
import '../features/sources/data/pikpak_source_preparation.dart';
import '../features/sources/data/provider_cloud_source.dart';
import '../features/sources/data/provider_source_actions.dart';
import '../features/sources/data/source_acquisition.dart';
import '../features/sources/data/source_acquisition_cleanup.dart';
import '../features/sources/data/source_binding_committer.dart';
import '../features/sources/data/source_download.dart';
import '../features/sources/data/source_file_ordering.dart';
import '../features/sources/data/source_magnet.dart';
import '../features/sources/data/source_playlist.dart';
import '../features/sources/data/source_playlist_resolver.dart';
import '../features/sources/data/source_single_episode.dart';
import '../features/sources/presentation/direct_source_binding.dart';
import '../features/sources/presentation/iptv_source_binding.dart';
import '../features/sources/presentation/local_source_binding.dart';
import '../features/sources/presentation/source_download_action.dart';
import '../features/sources/presentation/source_download_picker.dart';
import '../features/sources/presentation/source_provider_picker.dart';
import '../features/sources/presentation/torrent_source_binding.dart';
import '../models/playback_meta.dart';
import '../models/playlist_view_mode.dart';
import '../models/profiles/profile_policy.dart';
import '../models/quick_play_rules.dart';
import '../models/source_playlist_resolver.dart';
import '../models/torrent.dart';
import '../screens/video_player/models/playlist_entry.dart';
import '../theme/app_theme_scope.dart';
import '../utils/deovr_utils.dart' as deovr;
import '../utils/dialog_tap_guard.dart';
import '../utils/file_utils.dart';
import '../utils/filter_ladder.dart';
import '../utils/formatters.dart';
import '../utils/series_parser.dart';
import '../utils/torrent_coverage_detector.dart';
import '../widgets/debrid_action_sheet.dart';
import '../widgets/debrid_loading_overlay.dart';
import '../widgets/debrify_tv_channel_add_bridge.dart';
import '../widgets/not_cached_dialog.dart';
import '../widgets/pipeline_loading_overlay.dart';
import '../widgets/provider_picker_dialog.dart';
import 'alldebrid_service.dart';
import 'android_local_source_service.dart';
import 'debrid_service.dart';
import 'direct_source_authorization.dart';
import 'failed_saved_source.dart';
import 'iptv_source_search.dart';
import 'local_bound_source_service.dart';
import 'local_playback_resume_resolver.dart';
import 'media_server_service.dart';
import 'play_loader_style.dart';
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
        _snack(
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
        _snack(context, 'IPTV connection changed. Search sources again.');
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
      final committer = _validatedLaunchCommitter(
        resolverProvider ?? SeriesSource.addonDirectService,
        meta,
        sourceBindings: bindingOwner,
      );
      try {
        await VideoPlayerLauncher.push(
          context,
          _playerArgs(
            videoUrl: torrent.directUrl!,
            httpHeaders: torrent.httpHeaders,
            title: torrent.displayTitle,
            subtitle: torrent.source.isNotEmpty ? torrent.source : null,
            stremioSources: launchSources,
            stremioCurrentSourceIndex: launchSourceIndex,
            resolveSourceToPlaylist:
                (launchSources.length > 1 || fetcher != null)
                ? _lazyProviderResolver(committer)
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
          onQuickPlayNextEpisode: _nextEpisodeHandlerFor(
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
        _snack(context, 'External players are disabled for this profile.');
        return;
      }
      final uri = Uri.tryParse(torrent.directUrl!);
      if (uri == null) {
        _snack(context, 'Invalid stream URL.');
        return;
      }
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok && context.mounted) {
          _snack(context, 'Could not open link — no app to handle it.');
        }
      } catch (e) {
        if (context.mounted && bindingOwner.isCurrent) {
          _snack(context, 'Could not open link: $e');
        }
      }
      return;
    }

    final provider = await _pickProvider(
      context,
      canContinue: () => context.mounted && bindingOwner.isCurrent,
    );
    if (!context.mounted || !bindingOwner.isCurrent) return;
    if (provider == SourceProviderConfig.cancelled) return; // user dismissed the picker
    if (provider == null) {
      _snack(context, 'No debrid provider configured. Add one in Settings.');
      return;
    }
    final magnet = await sourceMagnet(torrent);
    if (!context.mounted || !bindingOwner.isCurrent) return;
    if (magnet == null) {
      _snack(context, 'This result has no magnet or infohash to play.');
      return;
    }
    final action = forcePlay ? 'play' : await _postAction(provider);
    if (!context.mounted || !bindingOwner.isCurrent) return;

    final loading = _showLoading(context, provider, torrent.displayTitle);
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
        _snack(
          context,
          'Files still processing on PikPak. Check the PikPak Files page later.',
        );
      }
      return;
    } on PikPakSourceFailed {
      loading.dismiss();
      if (context.mounted && bindingOwner.isCurrent) {
        _snack(context, 'Download failed on PikPak.');
      }
      return;
    } catch (e) {
      loading.dismiss();
      if (context.mounted && bindingOwner.isCurrent) {
        _snack(context, 'Could not resolve source: $e');
      }
      return;
    }
    loading.dismiss();
    if (!context.mounted || !bindingOwner.isCurrent) return;

    if (notCached != null) {
      await _handleNotCached(
        context,
        notCached,
        provider,
        magnet,
        sourceBindings: bindingOwner,
      );
      return;
    }
    if (resolved == null) {
      _snack(context, 'No playable source found for this result.');
      return;
    }

    switch (action) {
      case 'none':
        _snack(context, 'Torrent added to ${_label(provider)} successfully.');
        break;
      case 'open':
        if (resolved.isRarArchive) {
          _snack(context, 'Not available for RAR archives.');
        } else {
          resolved.openInTab?.call();
        }
        break;
      case 'copy':
        if (resolved.playUrl != null && resolved.playUrl!.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: resolved.playUrl!));
          if (context.mounted && bindingOwner.isCurrent) {
            _snack(
              context,
              'Torrent added to ${_label(provider)}! Download link copied to clipboard.',
            );
          }
        } else {
          _snack(
            context,
            'Added to ${_label(provider)}, but no link was available to copy.',
          );
        }
        break;
      case 'download':
        await _download(
          context,
          resolved,
          torrent,
          provider,
          sourceBindings: bindingOwner,
        );
        break;
      case 'playlist':
        await _addToPlaylist(
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
        await _showChooser(
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
        await _play(
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
        committer = _validatedLaunchCommitter(
          resolverProvider ?? SeriesSource.addonDirectService,
          meta,
          sourceBindings: bindingOwner,
        );
        final args = _playerArgs(
          videoUrl: direct.directUrl!,
          httpHeaders: direct.httpHeaders,
          title: direct.displayTitle,
          subtitle: direct.source.isNotEmpty ? direct.source : null,
          stremioSources: torrents,
          stremioCurrentSourceIndex: torrents.indexOf(direct),
          resolveSourceToPlaylist:
              (torrents.length > 1 || seriesFetcher != null)
              ? (resolverProvider == null
                    ? _lazyProviderResolver(committer)
                    : _resolverFor(resolverProvider, committer))
              : null,
          startupFailoverEnabled: true,
          startupResolverProvider: resolverProvider,
          onStremioSourceCommitted: committer.call,
          seriesSourceFetcher: seriesFetcher,
          meta: meta,
        );
        final nextEpisodeHandler = _nextEpisodeHandlerFor(
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
          strictProvider = await _pickProvider(
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
            ov ??= _showPipeline(
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
        ov ??= _showPipeline(
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
        await _launch(
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
        _snack(
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
        _snack(
          context,
          "This title's stream links appear to be offline. Open Sources to try one manually.",
        );
      }
      return;
    }

    final prov =
        provider ??
        await _pickProvider(
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
      _snack(context, 'No debrid provider configured. Add one in Settings.');
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
      _snack(context, 'No playable sources found for this title.');
      return;
    }
    // Standalone play (no loader passed by the search flow): show one now.
    ov ??= _showPipeline(
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
      _snack(
        context,
        'No instantly-playable source found. Open Sources to pick or download one.',
      );
      return;
    }
    final idx = torrents.indexOf(winner!);
    await _launch(
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
      _snack(context, 'No IMDb match to find sources for "$label".');
      return;
    }
    var cancelled = false;
    final resolving = showResolvingOverlay(
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
        _snack(
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
      await _playAddonStream(
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
        final played = await _playViaBound(
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
      await _playAddonStream(
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
      final handled = await _playAddonStream(
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
        await _pickProvider(
          context,
          canContinue: () => context.mounted && bindingOwner.isCurrent,
        );
    if (!context.mounted || !bindingOwner.isCurrent) return;
    if (provider == SourceProviderConfig.cancelled) return;
    if (provider == null) {
      if (addonFallbackAlreadySearched) {
        _snack(
          context,
          'No direct stream for "$label". Add a debrid provider in Settings for more sources.',
        );
        return;
      }
      // ignore: invalid_use_of_visible_for_testing_member
      if (!SourceSearchPlans.allowsAddonSearch(activeRules)) {
        _snack(
          context,
          'No debrid provider configured. Add one in Settings to use torrent-only Quick Play.',
        );
        return;
      }
      // No debrid provider — but some titles still have a direct addon stream
      // that plays without one. Run an addon-only search and let playBest open
      // a direct link; if there's none it shows the "add a provider" snack.
      await _playAddonStream(
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
    final overlay = _showPipeline(
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
      _applyLadderNote(overlay, ladder, packs);
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
          await _launch(
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
      if (context.mounted) _snack(context, 'Search failed: $e');
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
      _snack(context, 'No sources found for "$label".');
      return;
    }

    // The list was ranked before lazy IPTV probing so the fallback gate and
    // automatic playback agree on which provider comes first. [playBest]
    // performs its own final defensive ordering before selection.
    if (torrents.isEmpty) {
      closeLoading();
      _snack(context, 'No sources match your Quick Play rules for "$label".');
      return;
    }
    _applyLadderNote(overlay, ladder, torrents);
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

  static void _applyLadderNote(
    PipelineLoadingOverlay overlay,
    FilterLadder ladder,
    List<Torrent> ordered,
  ) {
    // ignore: invalid_use_of_visible_for_testing_member
    final note = SourceFilterLadder.ladderNote(ladder, ordered);
    if (note != null) overlay.setNote(note);
  }

  static Future<bool> _playAddonStream(
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
    final overlay = _showPipeline(
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
        _snack(context, 'This episode is not available from its catalog.');
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
      if (context.mounted) _snack(context, 'Search failed: $e');
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
        await _launch(
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
        _snack(
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
        _snack(
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
    _applyLadderNote(overlay, ladder, torrents);
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
          '${_seLabel(meta.season!, meta.episode!)} not found in local source. Falling back to search.',
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

  /// "S04E01"-style label for bound-source hint messages.
  static String _seLabel(int season, int episode) =>
      'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';

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
  static Future<bool> _playViaBound(
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
    final overlay = _showPipeline(
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
            await _launch(
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
                await _recoverAfterBoundStartupFailure(
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
            await _launch(
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
                await _recoverAfterBoundStartupFailure(
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
          await _launch(
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
              await _recoverAfterBoundStartupFailure(
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
                '${_seLabel(season, episode)} not in saved sources. Use Edit Source to change them.';
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
        await _launch(
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
            await _recoverAfterBoundStartupFailure(
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
    if (fallbackHint != null && context.mounted) _snack(context, fallbackHint);
    return false;
  }

  /// Continue after a saved source resolved successfully but the real player
  /// rejected it before startup committed. [remainingSources] preserves the
  /// saved priority order and [_playViaBound] keeps its exact-episode guards;
  /// only after those candidates fail do we re-enter search below the binding
  /// gate so the rejected source cannot loop.
  static Future<void> _recoverAfterBoundStartupFailure(
    BuildContext context,
    String imdbId,
    List<SeriesSource> remainingSources, {
    required String label,
    required PlaybackMeta meta,
    String? preferredProvider,
    bool skipLinkCache = false,
    required AutomaticSourceBindings sourceBindings,
  }) async {
    if (!context.mounted || !sourceBindings.isCurrent) return;
    if (remainingSources.isNotEmpty) {
      final played = await _playViaBound(
        context,
        imdbId,
        remainingSources,
        label: label,
        meta: meta,
        preferredProvider: preferredProvider,
        skipLinkCache: skipLinkCache,

        sourceBindings: sourceBindings,
      );
      if (played || (!context.mounted || !sourceBindings.isCurrent)) return;
    }
    await playFromSelection(
      context,
      imdbId: imdbId,
      isMovie: meta.contentType == 'movie',
      season: meta.season,
      episode: meta.episode,
      meta: meta,
      preferredProvider: preferredProvider,
      skipBoundSources: true,

      sourceBindings: sourceBindings,
    );
  }

  /// Pin [torrent] as the playback source for [imdbId]. Adds it to the chosen
  /// provider first to confirm it's instantly playable (Home only binds cached
  /// sources); on success stores a [SeriesSource] — movies keep one, series
  /// accumulate a priority list. Returns true if bound.
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
  }) => presentTorrentSourceBinding(
    context,
    imdbId: imdbId,
    cancelledProvider: SourceProviderConfig.cancelled,
    canContinue: canContinue,
    pickProvider: () => _pickProvider(context, canContinue: canContinue),
    showLoading: (provider) =>
        _showLoading(context, provider, torrent.name).dismiss,
    prepare: (provider) => preparation.prepare(
      provider,
      torrent,
      canContinue: canContinue,
    ),
    describe: (provider) => SeriesSource(
      torrentHash: torrent.infohash,
      torrentName: torrent.name,
      debridService: SourceProviderConfig.storedProviderKey(provider),
      debridTorrentId: '',
      boundAt: DateTime.now().millisecondsSinceEpoch,
      addonCatalogId: addonCatalogId,
      addonCatalogKey: addonCatalogKey,
    ),
    save: (source) => _persistManualBinding(
      source,
      imdbId: imdbId,
      isMovie: isMovie,
      saveBinding: saveBinding,
    ),
    providerLabel: _label,
  );

  /// Pin a playable Stremio addon stream without persisting its usually
  /// signed/temporary URL. Playback re-queries the same addon and stream
  /// profile for each movie play or requested series episode.
  static Future<bool> bindDirectSource(
    BuildContext context,
    Torrent torrent, {
    required String imdbId,
    required bool isMovie,
    Future<bool> Function(SeriesSource)? saveBinding,
    bool Function()? canContinue,
    String? addonCatalogId,
    String? addonCatalogKey,
  }) => presentDirectSourceBinding(
    context,
    torrent,
    imdbId: imdbId,
    canContinue: canContinue,
    authorize: DirectSourceAuthorization.authorize,
    describe: (source) => AutomaticSourceBindings.describe(
      source,
      SeriesSource.addonDirectService,
      addonCatalogId: addonCatalogId,
      addonCatalogKey: addonCatalogKey,
    ),
    save: (source) => _persistManualBinding(
      source,
      imdbId: imdbId,
      isMovie: isMovie,
      saveBinding: saveBinding,
    ),
  );

  /// Pin an IPTV movie or whole series by its secret-free catalog identity.
  /// Playback always resolves the current URL from the saved connection.
  static Future<bool> bindIptvSource(
    BuildContext context,
    Torrent torrent, {
    required String imdbId,
    required bool isMovie,
    Future<bool> Function(SeriesSource)? saveBinding,
    bool Function()? canContinue,
  }) => presentIptvSourceBinding(
    context,
    torrent,
    imdbId: imdbId,
    isMovie: isMovie,
    canContinue: canContinue,
    authorize: DirectSourceAuthorization.authorize,
    describe: (source) =>
        AutomaticSourceBindings.describe(source, SeriesSource.iptvDirectService),
    save: (source) => _persistManualBinding(
      source,
      imdbId: imdbId,
      isMovie: isMovie,
      saveBinding: saveBinding,
    ),
    log: logIptvSourceEvent,
  );

  /// Pin an ON-DEVICE file (movie) or folder (series) as [imdbId]'s source via
  /// the shared local picker. Desktop-only — the picker shows its own
  /// "unavailable on mobile" message on Android/iOS (matching Home). Returns
  /// true if a local source was pinned.
  static Future<bool> bindLocalSource(
    BuildContext context, {
    required String imdbId,
    required bool isMovie,
    Future<bool> Function(SeriesSource)? saveBinding,
    bool Function()? canContinue,
    required String title,
    String? year,
  }) => presentLocalSourceBinding(
    context,
    imdbId: imdbId,
    canContinue: canContinue,
    pick: () => isMovie
        ? LocalBoundSourceService.pickMovieSource(
            context,
            title: title,
            canContinue: canContinue,
            year: year,
          )
        : LocalBoundSourceService.pickSeriesSource(
            context,
            title: title,
            canContinue: canContinue,
          ),
    save: (source) => _persistManualBinding(
      source,
      imdbId: imdbId,
      isMovie: isMovie,
      saveBinding: saveBinding,
    ),
  );

  /// Compatibility writer for callers that have not migrated their binding
  /// persistence. Sources supplies its profile-owned repository callback.
  static Future<bool> _persistManualBinding(
    SeriesSource source, {
    required String imdbId,
    required bool isMovie,
    Future<bool> Function(SeriesSource)? saveBinding,
  }) async {
    if (saveBinding != null) return saveBinding(source);
    if (isMovie) {
      await SeriesSourceService.setSources(imdbId, [source]);
    } else {
      await SeriesSourceService.addSource(imdbId, source);
    }
    return true;
  }

  /// Whether on-device local binding is available on this platform (false on
  /// Android/iOS). Lets the UI hide/adjust the local-pin affordance.
  static bool get localBindingAvailable =>
      !LocalBoundSourceService.isLocalBindingDisabled;

  // ── Post-action branch handlers ────────────────────────────────────────────

  static Future<void> _play(
    BuildContext context,
    ResolvedSource r,
    Torrent torrent, {
    required String provider,
    PlaybackMeta? meta,
    List<Torrent>? sources,
    int sourceIndex = 0,
    required AutomaticSourceBindings sourceBindings,
  }) async {
    if (r.playUrl == null || r.playUrl!.isEmpty) {
      _snack(context, 'No playable link for this source.');
      return;
    }
    // Refuse a resolved single file that clearly isn't a video (parity with the
    // old screen's MIME check). Scoped to KEYWORD play (meta == null) so this
    // shared path doesn't add a new constraint to catalog board plays. Only
    // fires when we know the real filename; packs are video-filtered upstream.
    if (meta == null &&
        !r.hasPlaylist &&
        r.fileName != null &&
        r.fileName!.isNotEmpty &&
        !FileUtils.isVideoFile(r.fileName!)) {
      _snack(
        context,
        'Added to ${_label(provider)}, but the file is not a video.',
      );
      return;
    }
    // For keyword play (no catalog meta) prefer the provider's canonical file
    // name as the title, so the player's resume/Continue-Watching key matches
    // the same item played from the Debrid screen (old-screen parity). Catalog
    // play keeps its clean meta title.
    final playTitle =
        (meta == null &&
            !r.hasPlaylist &&
            r.fileName != null &&
            r.fileName!.isNotEmpty)
        ? r.fileName!
        : torrent.displayTitle;
    await _launch(
      context,
      r,
      playTitle,
      provider: provider,
      meta: meta,
      sources: sources ?? [torrent],
      sourceIndex: sourceIndex,

      sourceBindings: sourceBindings,
    );
  }

  /// Player "Next Episode" hand-back (matching Home's _quickPlayNextCallback):
  /// when a series playback runs out of playlist items and the user taps Next,
  /// both players hand the next episode back to the host — the Flutter player
  /// pops with a quickPlayNext payload and the Android TV activity requests it
  /// over the bridge (VideoPlayerLauncher resolves both to the same callback).
  /// Without this callback the launcher drops the request and the player just
  /// closes.
  ///
  /// [provider] is the debrid provider the CURRENT episode played with (null
  /// for direct addon streams and local bound sources) — the advance reuses it
  /// so a binge never re-prompts the provider picker mid-chain.
  static Future<void> Function(Map<String, dynamic>)? _nextEpisodeHandlerFor(
    BuildContext context,
    PlaybackMeta? meta, {
    String? provider,
    required AutomaticSourceBindings sourceBindings,
  }) {
    final imdbId = meta?.imdbId;
    if (meta == null ||
        meta.contentType != 'series' ||
        imdbId == null ||
        imdbId.isEmpty) {
      return null;
    }
    return (Map<String, dynamic> result) async {
      // Both players already resolved WHICH episode comes next (via
      // NextEpisodeService) — the payload names it directly.
      final season = result['season'] as int?;
      final episode = result['episode'] as int?;
      if (season == null || episode == null) return;
      final nextMeta = PlaybackMeta(
        imdbId: imdbId,
        contentType: 'series',
        season: season,
        episode: episode,
        title: meta.title,
        posterUrl: meta.posterUrl,
        year: meta.year,
        addonId: meta.addonId,
        catalogItem: meta.catalogItem,
        stremioAddonId: meta.stremioAddonId,
        stremioAddonKey: meta.stremioAddonKey,
        stremioCatalogId: meta.stremioCatalogId,
        // Keep scrobbling across the binge — a Trakt-row play must not stop
        // updating Trakt (and start saving duplicate local Continue Watching
        // entries) from episode 2 onward. Home drops this and goes stale
        // mid-binge; deliberately better here. traktProgressPercent IS
        // dropped: the next episode starts fresh, not at the previous
        // episode's resume point. Same for the Simkl pair.
        traktScrobble: meta.traktScrobble,
        simklScrobble: meta.simklScrobble,
        mdblistScrobble: meta.mdblistScrobble,
        resumePolicy: meta.resumePolicy,
        // Show-level artwork, so the loader keeps its backdrop and logo for
        // every episode of a binge instead of falling back to the poster from
        // episode 2 onward. Nothing in it is episode-specific.
        art: meta.art,
      );
      // Defer one frame (matching Home's addPostFrameCallback) so the previous
      // episode's entire play chain unwinds before the next one starts — an
      // awaited re-entry would nest one full search+play chain per episode,
      // retaining every prior episode's scopes across a binge.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted || !sourceBindings.isCurrent) return;
        unawaited(
          _advanceToNextEpisode(
            context,
            imdbId: imdbId,
            meta: nextMeta,
            provider: provider,

            sourceBindings: sourceBindings,
          ),
        );
      });
    };
  }

  /// Play the next episode of a binge. Provider-backed playbacks re-enter
  /// [playFromSelection] with the provider the previous episode used; direct
  /// addon-stream / local playbacks (no debrid provider) replay bound sources
  /// first, then the addon-stream flow — which plays direct streams without a
  /// provider, i.e. the same path that produced the episode being advanced.
  static Future<void> _advanceToNextEpisode(
    BuildContext context, {
    required String imdbId,
    required PlaybackMeta meta,
    String? provider,
    required AutomaticSourceBindings sourceBindings,
  }) async {
    logSourceSelection(
      'next_episode_start',
      season: meta.season,
      episode: meta.episode,
    );
    final label = meta.title ?? '';
    if (provider != null) {
      await playFromSelection(
        context,
        imdbId: imdbId,
        isMovie: false,
        season: meta.season,
        episode: meta.episode,
        meta: meta,
        preferredProvider: provider,

        sourceBindings: sourceBindings,
      );
      return;
    }
    final bound = (await SeriesSourceService.getSources(
      imdbId,
    )).where((source) => SourceCandidateChecks.bindingMatchesMeta(source, meta)).toList();
    if (!context.mounted || !sourceBindings.isCurrent) return;
    if (bound.isNotEmpty && meta.season != null && meta.episode != null) {
      final played = await _playViaBound(
        context,
        imdbId,
        bound,
        label: label,
        meta: meta,

        sourceBindings: sourceBindings,
      );
      if (played) return;
      if (!context.mounted || !sourceBindings.isCurrent) return;
    }
    final rules = await StorageService.getQuickPlayRules(isMovie: false);
    if (!context.mounted || !sourceBindings.isCurrent) return;
    await _playAddonStream(
      context,
      imdbId,
      isMovie: false,
      season: meta.season,
      episode: meta.episode,
      meta: meta,
      label: label,
      rules: rules,

      sourceBindings: sourceBindings,
    );
  }

  /// Shared meta → player-args plumbing. ONE place builds the content-identity
  /// fields for every push site — a field missed at a single site would
  /// silently break Continue Watching / scrobble / Next Episode for that entry
  /// path only.
  static VideoPlayerLaunchArgs _playerArgs({
    required String videoUrl,
    required String title,
    String? subtitle,
    List<PlaylistEntry>? playlist,
    int? startIndex,
    List<Torrent>? stremioSources,
    int? stremioCurrentSourceIndex,
    SourcePlaylistResolve? resolveSourceToPlaylist,
    bool startupFailoverEnabled = false,
    String? startupResolverProvider,
    Future<void> Function(Torrent)? onStremioSourceCommitted,
    Future<void> Function()? onStartupSourcesExhausted,
    bool startupHasRemainingSavedSources = false,
    SeriesSourceFetcher? seriesSourceFetcher,
    PlaybackMeta? meta,
    String? rdTorrentId,
    int? torboxTorrentId,
    PlaylistViewMode? viewMode,
    Map<String, String>? httpHeaders,
  }) => VideoPlayerLaunchArgs(
    // External apps receive only the URL, not media-server session headers.
    // Continuous shuffle also needs the in-app episode-fetch/EOF callbacks.
    disableExternalPlayer:
        (meta?.initialContinuousShuffle ?? false) ||
        (httpHeaders?.keys.any((key) => key.toLowerCase() == 'x-emby-token') ??
            false),
    initialContinuousShuffle: meta?.initialContinuousShuffle ?? false,
    videoUrl: videoUrl,
    httpHeaders: httpHeaders,
    title: title,
    subtitle: subtitle,
    playlist: playlist,
    startIndex: startIndex,
    viewMode: viewMode,
    stremioSources: stremioSources,
    stremioCurrentSourceIndex: stremioCurrentSourceIndex,
    resolveSourceToPlaylist: resolveSourceToPlaylist,
    startupFailoverEnabled: startupFailoverEnabled,
    startupResolverProvider: startupResolverProvider,
    onStremioSourceCommitted: onStremioSourceCommitted,
    onStartupSourcesExhausted: onStartupSourcesExhausted,
    startupHasRemainingSavedSources: startupHasRemainingSavedSources,
    seriesSourceFetcher: seriesSourceFetcher,
    contentImdbId: meta?.progressIdentity,
    contentType: meta?.contentType,
    contentSeason: meta?.season,
    contentEpisode: meta?.episode,
    contentTitle: meta?.title,
    posterUrl: meta?.posterUrl,
    contentYear: meta?.year,
    addonId: meta?.addonId,
    suppressTrackerAutoSync: meta?.hasStremioEpisodeIdentity ?? false,
    traktScrobble: meta?.hasStremioEpisodeIdentity == true
        ? false
        : meta?.traktScrobble ?? false,
    traktProgressPercent: meta?.hasStremioEpisodeIdentity == true
        ? null
        : meta?.traktProgressPercent,
    simklScrobble: meta?.hasStremioEpisodeIdentity == true
        ? false
        : meta?.simklScrobble ?? false,
    simklProgressPercent: meta?.hasStremioEpisodeIdentity == true
        ? null
        : meta?.simklProgressPercent,
    mdblistScrobble: meta?.hasStremioEpisodeIdentity == true
        ? false
        : meta?.mdblistScrobble ?? false,
    mdblistProgressPercent: meta?.hasStremioEpisodeIdentity == true
        ? null
        : meta?.mdblistProgressPercent,
    resumePolicy: meta?.resumePolicy ?? PlaybackResumePolicy.sourceSpecific,
    // Debrid torrent ids let the player back-fill poster/IMDb onto a saved
    // Playlist-library entry and power the in-player "Fix Metadata" action
    // (matching Home). PikPak is intentionally omitted: the launcher wants a
    // collection/folder id, but _Resolved only carries a per-file id.
    rdTorrentId: rdTorrentId,
    torboxTorrentId: torboxTorrentId?.toString(),
  );

  @visibleForTesting
  static VideoPlayerLaunchArgs playerArgsForTesting(
    PlaybackMeta? meta, {
    Map<String, String>? httpHeaders,
  }) => _playerArgs(videoUrl: 'video', title: 'Title', meta: meta, httpHeaders: httpHeaders);

  static bool _isNonDebridLaunchProvider(String provider) =>
      provider == SeriesSource.localService ||
      provider == SeriesSource.addonDirectService ||
      provider == SeriesSource.mediaServerService ||
      provider == SeriesSource.iptvDirectService;

  /// In-player Sources-switcher resolver for launches that didn't go through a
  /// debrid provider (direct addon streams). Direct streams resolve without
  /// one; a torrent switch silently uses the default/first-configured provider
  /// (matching Home's _createSourcePlaylistResolver) and fails gracefully
  /// (null) when none is configured.
  static SourcePlaylistResolve _lazyProviderResolver(
    SourceBindingCommitter committer,
  ) => _resolverFor(null, committer);

  /// Launch the player. Passes the full source list + a resolver (so the player
  /// shows the in-player "Sources" switcher) and content metadata (so Continue
  /// Watching, subtitles and the Episodes button work) — matching Home.
  static Future<void> _launch(
    BuildContext context,
    ResolvedSource r,
    String title, {
    required String provider,
    String? recoveryProvider,
    PlaybackMeta? meta,
    List<Torrent>? sources,
    int sourceIndex = 0,
    // "Load more sources" backend for the player's series source tabs (packs
    // vs episodes) — null for movies/keyword plays, which keep the flat list.
    SeriesSourceFetcher? seriesFetcher,
    // The play flow's still-showing loader, when the caller kept it up. It
    // covers the whole launch prep (auto-bind writes, the TV payload build
    // with its debrid link resolution, the native activity start) and the
    // launcher dismisses it only when the player actually takes the screen —
    // closing the detail-screen flash between "loading" and "playing".
    PipelineLoadingOverlay? overlay,
    bool startupFailoverEnabled = false,
    Future<void> Function()? onStartupSourcesExhausted,
    bool startupHasRemainingSavedSources = false,
    required AutomaticSourceBindings sourceBindings,
  }) async {
    // Once push() takes the handoff callback the LAUNCHER owns the dismissal
    // (player-visible time, or its own always-fires safety net); the finally
    // here only covers exits before that point. dismiss() is idempotent.
    var loaderHandedToLauncher = false;
    SourceBindingCommitter? committer;
    try {
      // Secondary metadata line (file size / source / file count), matching Home.
      final winner =
          (sources != null && sourceIndex >= 0 && sourceIndex < sources.length)
          ? sources[sourceIndex]
          : null;
      logSourceSelection(
        'launch_candidate',
        source: winner,
        index: sourceIndex,
        season: meta?.season,
        episode: meta?.episode,
        reason: startupFailoverEnabled
            ? 'automatic_with_fallback'
            : 'explicit_or_saved',
      );
      String? subtitleLine;
      if (r.hasPlaylist) {
        subtitleLine = '${r.playlist!.length} files';
      } else if (winner != null) {
        subtitleLine = winner.sizeBytes > 0
            ? Formatters.formatFileSize(winner.sizeBytes)
            : (winner.source.isNotEmpty ? winner.source : null);
      }
      // Organize the playlist as a TV series when the file names look like one, so
      // a keyword-launched season pack groups by season/episode and "next" walks
      // episode order — parity with the old screen. Scoped to KEYWORD play
      // (meta == null): catalog already drives series/movie view from its own
      // contentType, so this shared launcher must not override that. We pass
      // `series` only when detected and leave it null otherwise (null lets the
      // launcher's contentType fallback win).
      final PlaylistViewMode? viewMode =
          (meta == null && r.hasPlaylist && _isSeriesPlaylist(r.playlist!))
          ? PlaylistViewMode.series
          : null;
      // VR hand-off (parity with the old search screen): for a single video file
      // played from KEYWORD search (meta == null), when the user's VR mode says
      // so, play in DeoVR instead of the in-app player. Scoped to keyword so this
      // shared launcher doesn't newly divert catalog board plays. Packs keep the
      // normal player (DeoVR takes one video).
      if (meta == null && !r.hasPlaylist && await _shouldUseDeoVR(title)) {
        // DeoVR runs its own dialog flow — drop the loader before it.
        overlay?.dismiss();
        if (!context.mounted || !sourceBindings.isCurrent) return;
        await _launchWithDeoVR(context, videoUrl: r.playUrl!, filename: title);
        return;
      }
      // Args built BEFORE the flag flips: a throw while constructing them
      // must still hit the finally's dismiss, since push() never ran.
      // Snapshot the provider used for any fetched torrent candidates. Native
      // startup must know it before recovery so PikPak's acquisition cap also
      // applies when the initial saved source is a direct link.
      final resolverProvider = _isNonDebridLaunchProvider(provider)
          ? recoveryProvider ??
                await SourceProviderConfig.defaultConfiguredProvider(
                  canContinue: () =>
                      context.mounted && sourceBindings.isCurrent,
                )
          : provider;
      if (!context.mounted || !sourceBindings.isCurrent) return;
      committer = _isNonDebridLaunchProvider(provider)
          ? _lazySourceCommitter(
              meta,
              preferredProvider: resolverProvider,
              sourceBindings: sourceBindings,
            )
          : _validatedLaunchCommitter(
              provider,
              meta,
              sourceBindings: sourceBindings,
            );
      final args = _playerArgs(
        videoUrl: r.playUrl!,
        httpHeaders: r.httpHeaders,
        title: title,
        subtitle: subtitleLine,
        playlist: r.hasPlaylist ? r.playlist : null,
        startIndex: r.hasPlaylist ? r.startIndex : null,
        stremioSources: sources,
        stremioCurrentSourceIndex: sources != null ? sourceIndex : null,
        // A single-source launch still needs the resolver when the fetcher is
        // along: "Load more" grows the list mid-session and the new entries
        // must be switchable. A bound 'local' launch has no debrid provider —
        // the lazy variant resolves one silently at switch time.
        resolveSourceToPlaylist:
            (sources != null &&
                sources.isNotEmpty &&
                (sources.length > 1 || seriesFetcher != null))
            ? (resolverProvider == null
                  ? _lazyProviderResolver(committer)
                  : _resolverFor(resolverProvider, committer))
            : null,
        startupFailoverEnabled: startupFailoverEnabled,
        startupResolverProvider: resolverProvider,
        onStremioSourceCommitted: committer.call,
        onStartupSourcesExhausted: onStartupSourcesExhausted,
        startupHasRemainingSavedSources: startupHasRemainingSavedSources,
        seriesSourceFetcher: seriesFetcher,
        meta: meta,
        rdTorrentId: r.rdTorrentId,
        torboxTorrentId: r.torboxTorrentId,
        viewMode: viewMode,
      );
      // 'local' isn't a debrid provider the advance could search with — the
      // null makes the advance replay bound sources first, then addon streams.
      final nextEpisodeHandler = _nextEpisodeHandlerFor(
        context,
        meta,
        provider: _isNonDebridLaunchProvider(provider) ? null : provider,

        sourceBindings: sourceBindings,
      );
      loaderHandedToLauncher = overlay != null;
      await VideoPlayerLauncher.push(
        context,
        args,
        retainSourceSession: committer.retain,
        sourceOwner: committer.bindings.owner,
        canContinue: () => committer!.isCurrent,
        onPlayerHandoff: overlay?.dismiss,
        onQuickPlayNextEpisode: nextEpisodeHandler,
      );
    } finally {
      committer?.close();
      if (!loaderHandedToLauncher) overlay?.dismiss();
    }
  }

  /// Whether VR playback (DeoVR) should be used for [filename], per the user's
  /// VR-mode setting. Android-only. Ported from the old search screen.
  static Future<bool> _shouldUseDeoVR(String filename) async {
    if (!Platform.isAndroid) return false;
    final vrMode = await StorageService.getQuickPlayVrMode();
    switch (vrMode) {
      case 'always':
        return true;
      case 'auto':
        return deovr.isVrContent(filename);
      case 'disabled':
      default:
        return false;
    }
  }

  /// Hand a single video file off to DeoVR: pick a screen/stereo format (auto
  /// from the filename or the user's defaults, optionally confirmed via a
  /// dialog), upload a DeoVR JSON descriptor to jsonblob, then launch the
  /// `deovr://` intent. Ported verbatim from the old search screen.
  static Future<void> _launchWithDeoVR(
    BuildContext context, {
    required String videoUrl,
    required String filename,
  }) async {
    if (!Platform.isAndroid) return;
    // Capture the root navigator while context is synchronously valid, so the
    // loading overlay can always be dismissed even if the widget unmounts during
    // the awaited upload below.
    final rootNav = Navigator.of(context, rootNavigator: true);

    final autoDetectFormat =
        await StorageService.getQuickPlayVrAutoDetectFormat();
    final showFormatDialog = await StorageService.getQuickPlayVrShowDialog();

    String screenType;
    String stereoMode;
    if (autoDetectFormat) {
      final detected = deovr.detectVRFormat(filename);
      screenType = detected.screenType;
      stereoMode = detected.stereoMode;
    } else {
      screenType = await StorageService.getQuickPlayVrDefaultScreenType();
      stereoMode = await StorageService.getQuickPlayVrDefaultStereoMode();
    }

    if (showFormatDialog && context.mounted) {
      String selectedScreenType = screenType;
      String selectedStereoMode = stereoMode;
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('DeoVR Format'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  filename,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Screen Type',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedScreenType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: deovr.screenTypeLabels.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedScreenType = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  'Stereo Mode',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedStereoMode,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: deovr.stereoModeLabels.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedStereoMode = value);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  DialogTapGuard.markKeyAction();
                  Navigator.of(context).pop(false);
                },
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () {
                  DialogTapGuard.markKeyAction();
                  Navigator.of(context).pop(true);
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play'),
              ),
            ],
          ),
        ),
      );
      if (result != true || !context.mounted) return;
      screenType = selectedScreenType;
      stereoMode = selectedStereoMode;
    }

    // Tracks whether the blocking loading dialog is still on screen, so the
    // catch below never pops the underlying screen after we've already
    // dismissed the dialog (e.g. a failed `intent.launch()` when DeoVR isn't
    // installed would otherwise bounce the user back a screen).
    bool loadingShown = false;
    try {
      if (context.mounted) {
        loadingShown = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              const Center(child: CircularProgressIndicator()),
        );
      }

      final json = deovr.generateDeoVRJson(
        videoUrl: videoUrl,
        title: filename,
        screenType: screenType,
        stereoMode: stereoMode,
      );
      final response = await http.post(
        Uri.parse('https://jsonblob.com/api/jsonBlob'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(json),
      );
      if (response.statusCode != 201) {
        throw Exception('Failed to upload JSON: ${response.statusCode}');
      }
      final location = response.headers['location'];
      if (location == null) {
        throw Exception('No location header in response');
      }
      final jsonUrl = 'https://jsonblob.com$location';

      if (loadingShown) {
        rootNav.pop();
        loadingShown = false;
      }

      final intent = AndroidIntent(
        action: 'action_view',
        data: 'deovr://$jsonUrl',
      );
      await intent.launch();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Launching DeoVR...'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (loadingShown) rootNav.pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open with DeoVR: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Builds the in-player source-switch resolver: given another [Torrent] the
  /// user picked, add it to [provider] and return its playlist (so switching
  /// sources works without leaving the player).
  static SourcePlaylistResolve _resolverFor(
    String? provider,
    SourceBindingCommitter committer,
  ) => SourcePlaylistResolver(
    owner: committer.bindings.owner,
    provider: provider,
    canContinue: () => committer.isCurrent,
    chooseProvider: (active) => SourceProviderConfig.defaultConfiguredProvider(canContinue: active),
  ).resolve;

  static SourceBindingCommitter _validatedLaunchCommitter(
    String provider,
    PlaybackMeta? meta, {
    required AutomaticSourceBindings sourceBindings,
  }) => SourceBindingCommitter(
    bindings: sourceBindings,
    meta: meta,
    provider: provider,
    chooseProvider: (active) => SourceProviderConfig.defaultConfiguredProvider(canContinue: active),
  );

  @visibleForTesting
  static Future<void> Function(Torrent) validatedSourceCommitterForTesting(
    String provider,
    PlaybackMeta? meta,
  ) => _validatedLaunchCommitter(
    provider,
    meta,
    sourceBindings: AutomaticSourceBindings.capture(),
  ).call;

  static SourceBindingCommitter _lazySourceCommitter(
    PlaybackMeta? meta, {
    String? preferredProvider,
    required AutomaticSourceBindings sourceBindings,
  }) => SourceBindingCommitter(
    bindings: sourceBindings,
    meta: meta,
    provider: preferredProvider,
    lazy: true,
    chooseProvider: (active) => SourceProviderConfig.defaultConfiguredProvider(canContinue: active),
  );

  /// Native media-server streams need credential-aware background downloads,
  /// including redirect and resource-revocation handling, before enabling this.
  static bool supportsDirectStreamDownload(Torrent torrent) =>
      SourceDownload.supports(torrent);

  /// Download a direct/external addon stream to device (parity with the old
  /// screen's direct-stream "Download to device" action). Follows redirects
  /// first — MediaFusion-style playback URLs 30x-hop to the real file — then
  /// queues the resolved URL.
  static Future<void> downloadDirectStream(
    BuildContext context,
    Torrent torrent,
  ) => downloadSource(context, torrent, const SourceDownload());

  /// User-requested provider actions (download, playlist add, ZIP, transfer,
  /// keep-on-provider) finish once accepted, even if the user leaves the
  /// screen meanwhile — as before the refactor. The operations still reject a
  /// profile switch through their captured owner, and every snackbar checks
  /// `context.mounted` itself.
  static bool _acceptedProviderAction() => true;

  static Future<void> _download(
    BuildContext context,
    ResolvedSource r,
    Torrent torrent,
    String provider, {
    required AutomaticSourceBindings sourceBindings,
  }) async {
    final actions = ProviderSourceActions(
      owner: sourceBindings.owner,
      canContinue: _acceptedProviderAction,
    );
    if (!context.mounted || !actions.isCurrent) return;
    if (r.playlist != null && r.playlist!.length > 1) {
      final chosen = await showSourceDownloadPicker(context, r.playlist!);
      if (chosen == null || chosen.isEmpty || !actions.isCurrent) return;
      final n = await actions.queueEntries(
        chosen,
        provider: provider,
        torrentName: torrent.displayTitle,
      );
      if (context.mounted && actions.isCurrent) {
        _snack(
          context,
          n > 0
              ? 'Queued $n file(s) for download.'
              : 'Could not queue downloads.',
        );
      }
      return;
    }
    if (r.playlist?.isNotEmpty == true) {
      final n = await actions.queueEntries(
        r.playlist!,
        provider: provider,
        torrentName: torrent.displayTitle,
      );
      if (context.mounted && actions.isCurrent) {
        _snack(
          context,
          n > 0 ? 'Download queued.' : 'Could not queue download.',
        );
      }
      return;
    }
    final url = r.downloadUrls.isNotEmpty ? r.downloadUrls.first : null;
    if (url == null) {
      _snack(context, 'Nothing to download for this source.');
      return;
    }
    try {
      await actions.queueUrl(
        url,
        provider: provider,
        fileName: r.fileName ?? torrent.displayTitle,
        torrentName: torrent.displayTitle,
      );
    } catch (_) {}
    // Preserve the legacy single-URL feedback, including its best-effort enqueue.
    if (context.mounted && actions.isCurrent) {
      _snack(context, 'Download queued.');
    }
  }

  static Future<void> _addToPlaylist(
    BuildContext context,
    ResolvedSource r,
    Torrent torrent,
    String provider, {
    PlaybackMeta? meta,
    required AutomaticSourceBindings sourceBindings,
  }) async {
    final playlist = SourcePlaylist(
      owner: sourceBindings.owner,
      canContinue: _acceptedProviderAction,
    );
    if (!playlist.isCurrent) return;
    final ok = await playlist.add(r, torrent, provider, meta: meta);
    if (context.mounted && playlist.isCurrent) {
      _snack(context, ok ? 'Added to playlist.' : 'Already in playlist.');
    }
  }

  /// The app's real post-add chooser (glass card + styled tiles), with the full
  /// option set — Play / Download / Add to playlist / Add to channel / Open in
  /// provider tab — matching Home's per-provider sheets.
  static Future<void> _showChooser(
    BuildContext context,
    ResolvedSource r,
    Torrent torrent,
    String provider, {
    String? magnet,
    PlaybackMeta? meta,
    List<Torrent>? sources,
    int sourceIndex = 0,
    String searchKeyword = '',
    required AutomaticSourceBindings sourceBindings,
  }) async {
    final hasVideo = r.playUrl != null && r.playUrl!.isNotEmpty;
    final name = torrent.displayTitle;
    await showDebridActionSheet(
      context,
      providerLabel: _label(provider),
      torrentName: name,
      gradient: _providerGradient(provider),
      providerIcon: _providerIcon(provider),
      subtitle: hasVideo
          ? 'Ready on ${_label(provider)}. Choose your next step.'
          : 'Added to ${_label(provider)}.',
      actions: [
        DebridActionItem(
          icon: Icons.play_circle_fill_rounded,
          color: const Color(0xFF10B981),
          title: 'Play now',
          subtitle: 'Stream it right away.',
          pillLabel: 'Play',
          enabled: hasVideo,
          onTap: () => unawaited(
            _play(
              context,
              r,
              torrent,
              provider: provider,
              meta: meta,
              sources: sources,
              sourceIndex: sourceIndex,

              sourceBindings: sourceBindings,
            ),
          ),
        ),
        // The service refuses anyway, but a profile that can't download
        // shouldn't be offered a button that only fails.
        if (ProfilePolicyGuard.allowsSync(ProfileFeature.downloads))
          DebridActionItem(
            icon: Icons.download_rounded,
            color: const Color(0xFF3B82F6),
            title: 'Download to device',
            subtitle: 'Grab the file(s) via ${_label(provider)}.',
            pillLabel: 'Download',
            onTap: () => unawaited(
              _download(
                context,
                r,
                torrent,
                provider,
                sourceBindings: sourceBindings,
              ),
            ),
          ),
        DebridActionItem(
          icon: Icons.playlist_add_rounded,
          color: const Color(0xFF8B5CF6),
          title: 'Add to playlist',
          subtitle: 'Save it to your playlist for later.',
          pillLabel: 'Playlist',
          enabled: hasVideo,
          onTap: () => unawaited(
            _addToPlaylist(
              context,
              r,
              torrent,
              provider,
              meta: meta,
              sourceBindings: sourceBindings,
            ),
          ),
        ),
        DebridActionItem(
          icon: Icons.connected_tv,
          color: const Color(0xFF14B8A6),
          title: 'Add to channel',
          subtitle: 'Cache this torrent in a Debrify TV channel.',
          onTap: () => unawaited(
            DebrifyTvChannelAddBridge.addTorrentsToChannel(
              context,
              torrents: [torrent],
              searchKeyword: searchKeyword,
              owner: sourceBindings.owner,
              canContinue: () => sourceBindings.isCurrent,
            ),
          ),
        ),
        // TorBox power actions: download the whole-torrent ZIP to device, or
        // copy its permalink (parity with the old screen's TorBox download menu).
        if (provider == 'torbox' && r.torboxTorrentId != null) ...[
          DebridActionItem(
            icon: Icons.folder_zip_rounded,
            color: const Color(0xFFA78BFA),
            title: 'Download as ZIP',
            subtitle: 'Download all files as a ZIP to this device.',
            onTap: () => unawaited(
              _downloadTorboxZip(
                context,
                r.torboxTorrentId!,
                name,
                sourceBindings: sourceBindings,
              ),
            ),
          ),
          DebridActionItem(
            icon: Icons.link_rounded,
            color: const Color(0xFFEC4899),
            title: 'Copy Download Link (Zip)',
            subtitle: 'Copy ZIP download link to clipboard.',
            onTap: () => unawaited(
              _copyTorboxZipLink(
                context,
                r.torboxTorrentId!,
                sourceBindings: sourceBindings,
              ),
            ),
          ),
        ],
        // Premiumize power actions (need the magnet — cloud transfer + ZIP).
        if (provider == 'premiumize' && magnet != null) ...[
          DebridActionItem(
            icon: Icons.cloud_upload_rounded,
            color: const Color(0xFFF59E0B),
            title: 'Transfer to Premiumize',
            subtitle: 'Add this torrent to your Premiumize cloud.',
            onTap: () => unawaited(
              _premiumizeTransfer(
                context,
                magnet,
                sourceBindings: sourceBindings,
              ),
            ),
          ),
          DebridActionItem(
            icon: Icons.folder_zip_rounded,
            color: const Color(0xFFA78BFA),
            title: 'Download as ZIP',
            subtitle: 'Transfer to cloud and download all files as a ZIP.',
            onTap: () => unawaited(
              _premiumizeZip(
                context,
                magnet,
                name,
                copyOnly: false,
                sourceBindings: sourceBindings,
              ),
            ),
          ),
          DebridActionItem(
            icon: Icons.link_rounded,
            color: const Color(0xFFEC4899),
            title: 'Copy ZIP Link',
            subtitle: 'Copy ZIP download link to clipboard.',
            onTap: () => unawaited(
              _premiumizeZip(
                context,
                magnet,
                name,
                copyOnly: true,
                sourceBindings: sourceBindings,
              ),
            ),
          ),
        ],
        if (r.openInTab != null)
          DebridActionItem(
            icon: Icons.open_in_new_rounded,
            color: const Color(0xFF6366F1),
            title: 'Open in provider tab',
            subtitle: r.isRarArchive
                ? 'Not available for RAR archives'
                : 'View it in ${_label(provider)}.',
            enabled: !r.isRarArchive,
            onTap: () {
              if (context.mounted && sourceBindings.isCurrent) {
                r.openInTab!.call();
              }
            },
          ),
      ],
    );
  }

  // ── Provider-specific power actions (TorBox / Premiumize) ───────────────────

  static Future<void> _copyTorboxZipLink(
    BuildContext context,
    int torrentId, {
    required AutomaticSourceBindings sourceBindings,
  }) async {
    final actions = ProviderSourceActions(
      owner: sourceBindings.owner,
      canContinue: _acceptedProviderAction,
    );
    if (!context.mounted || !actions.isCurrent) return;
    final String? url;
    try {
      url = await actions.torboxZipUrl(torrentId);
    } catch (_) {
      return;
    }
    if (url == null || !actions.isCurrent) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted && actions.isCurrent) {
      _snack(context, 'ZIP download link copied to clipboard!');
    }
  }

  static Future<void> _downloadTorboxZip(
    BuildContext context,
    int torrentId,
    String name, {
    required AutomaticSourceBindings sourceBindings,
  }) async {
    final actions = ProviderSourceActions(
      owner: sourceBindings.owner,
      canContinue: _acceptedProviderAction,
    );
    if (!context.mounted || !actions.isCurrent) return;
    try {
      final queued = await actions.queueTorboxZip(torrentId, name);
      if (context.mounted && queued && actions.isCurrent) {
        _snack(context, 'ZIP download queued.');
      }
    } catch (_) {
      if (context.mounted && actions.isCurrent) {
        _snack(context, 'Failed to queue ZIP download.');
      }
    }
  }

  static Future<void> _premiumizeTransfer(
    BuildContext context,
    String magnet, {
    required AutomaticSourceBindings sourceBindings,
  }) async {
    final actions = ProviderSourceActions(
      owner: sourceBindings.owner,
      canContinue: _acceptedProviderAction,
    );
    if (!context.mounted || !actions.isCurrent) return;
    try {
      final accepted = await actions.transferPremiumize(magnet);
      if (context.mounted && accepted && actions.isCurrent) {
        _snack(
          context,
          'Added to Premiumize. It will be available once the download finishes.',
        );
      }
    } catch (_) {
      if (context.mounted && actions.isCurrent) {
        _snack(context, 'Failed to transfer to Premiumize.');
      }
    }
  }

  static Future<void> _premiumizeZip(
    BuildContext context,
    String magnet,
    String name, {
    required bool copyOnly,
    required AutomaticSourceBindings sourceBindings,
  }) async {
    final actions = ProviderSourceActions(
      owner: sourceBindings.owner,
      canContinue: _acceptedProviderAction,
    );
    if (!context.mounted || !actions.isCurrent) return;
    DebridLoadingHandle? loading;
    String? url;
    var failed = false;
    try {
      url = await actions.premiumizeZipUrl(
        magnet,
        onStarted: () {
          if (context.mounted) {
            loading = DebridLoadingOverlay.showPremiumize(context, name);
          }
        },
      );
    } catch (_) {
      failed = true;
    } finally {
      loading?.dismiss();
    }
    if (failed) {
      if (context.mounted && actions.isCurrent) {
        _snack(
          context,
          copyOnly ? 'Failed to generate ZIP link.' : 'Failed to generate ZIP.',
        );
      }
      return;
    }
    if (url == null || !actions.isCurrent) return;
    try {
      if (copyOnly) {
        await Clipboard.setData(ClipboardData(text: url));
        if (context.mounted && actions.isCurrent) {
          _snack(context, 'ZIP download link copied to clipboard!');
        }
      } else {
        await actions.queueUrl(
          url,
          provider: 'premiumize',
          fileName: '$name.zip',
          torrentName: name,
        );
        if (context.mounted && actions.isCurrent) {
          _snack(context, 'ZIP download queued successfully.');
        }
      }
    } catch (_) {
      if (context.mounted && actions.isCurrent) {
        _snack(
          context,
          copyOnly ? 'Failed to generate ZIP link.' : 'Failed to generate ZIP.',
        );
      }
    }
  }

  static List<Color> _providerGradient(String provider) {
    switch (provider) {
      case 'debrid':
        return const [Color(0xFF10B981), Color(0xFF059669)];
      case 'torbox':
        return const [Color(0xFF8B5CF6), Color(0xFF7C3AED)];
      case 'premiumize':
        return const [Color(0xFFF59E0B), Color(0xFFD97706)];
      case 'alldebrid':
        return const [Color(0xFF26A69A), Color(0xFF00796B)];
      case 'pikpak':
        return const [Color(0xFF6366F1), Color(0xFF4338CA)];
      default:
        return const [Color(0xFF6366F1), Color(0xFF4338CA)];
    }
  }

  static IconData _providerIcon(String provider) {
    switch (provider) {
      case 'debrid':
        return Icons.cloud_download_rounded;
      case 'torbox':
        return Icons.flash_on_rounded;
      case 'premiumize':
        return Icons.workspace_premium_rounded;
      case 'alldebrid':
        return Icons.all_inclusive_rounded;
      case 'pikpak':
        return Icons.cloud_circle_rounded;
      default:
        return Icons.cloud_download_rounded;
    }
  }

  // ── Not-cached handling (mirrors Home UX: warn, then keep-downloading) ──────

  static Future<void> _handleNotCached(
    BuildContext context,
    Object marker,
    String provider,
    String magnet, {
    required AutomaticSourceBindings sourceBindings,
  }) async {
    final actions = ProviderSourceActions(
      owner: sourceBindings.owner,
      canContinue: _acceptedProviderAction,
    );
    if (!context.mounted || !actions.isCurrent) return;
    final keep = await showNotCachedDialog(context, _label(provider));
    if (!context.mounted || !actions.isCurrent) return;
    try {
      await actions.decideNotCached(marker, provider, magnet, keep: keep);
    } catch (_) {
      if (!context.mounted || !actions.isCurrent) return;
      rethrow;
    }
    if (context.mounted && keep && actions.isCurrent) {
      _snack(
        context,
        'Added — it will download on ${_label(provider)}. Play it once ready.',
      );
    }
  }

  // ── Provider resolution ────────────────────────────────────────────────────

  /// Resolves which provider to use. Honours the default; when none is set and
  /// more than one is configured, asks the user (mirrors Home's behaviour).
  static Future<String?> _pickProvider(
    BuildContext context, {
    bool Function()? canContinue,
  }) => pickSourceProvider(
    context,
    cancelledProvider: SourceProviderConfig.cancelled,
    canContinue: canContinue,
    loadConfiguration: () => SourceProviderConfig.configuredProviders(canContinue: canContinue),
    optionFor: (provider) => ProviderPickerOption(
      id: provider,
      label: _label(provider),
      gradient: _providerGradient(provider),
      icon: _providerIcon(provider),
    ),
    remember: (provider) => StorageService.setDefaultTorrentProvider(
      provider,
      canContinue: canContinue,
    ),
  );

  static Future<String> _postAction(String provider) async {
    switch (provider) {
      case 'torbox':
        return StorageService.getTorboxPostTorrentAction();
      case 'premiumize':
        return StorageService.getPremiumizePostTorrentAction();
      case 'alldebrid':
        return StorageService.getAllDebridPostTorrentAction();
      case 'pikpak':
        return StorageService.getPikPakPostTorrentAction();
      default:
        return StorageService.getPostTorrentAction();
    }
  }

  // ── File pickers: largest file that looks like video ───────────────────────

  /// True when a resolved playlist's file names look like a TV series (multiple
  /// files parseable as season/episode), so it should play in series view mode.
  static bool _isSeriesPlaylist(List<PlaylistEntry> entries) {
    if (entries.length <= 1) return false;
    final names = [for (final e in entries) sourceFileName(e.title)];
    return SeriesParser.isSeriesPlaylist(names);
  }

  static String _label(String provider) {
    switch (provider) {
      case 'preparing':
        return 'Preparing';
      case 'debrid':
        return 'Real-Debrid';
      case 'torbox':
        return 'TorBox';
      case 'premiumize':
        return 'Premiumize';
      case 'alldebrid':
        return 'AllDebrid';
      case 'pikpak':
        return 'PikPak';
      case SeriesSource.localService:
        return 'On-device';
      case SeriesSource.addonDirectService:
        return 'Direct addon';
      case SeriesSource.iptvDirectService:
        return 'IPTV';
      case SeriesSource.mediaServerService:
        return 'Media server';
      case 'stream':
        return 'Stream';
      default:
        return provider;
    }
  }

  /// Two-letter provider glyph for the Pipeline loader's provider chip.
  static String _providerCode(String provider) {
    switch (provider) {
      case 'preparing':
        return '···';
      case 'debrid':
        return 'RD';
      case 'torbox':
        return 'TB';
      case 'premiumize':
        return 'PM';
      case 'alldebrid':
        return 'AD';
      case 'pikpak':
        return 'PP';
      case 'stream':
        return 'TV';
      case SeriesSource.addonDirectService:
        return 'DL';
      case SeriesSource.iptvDirectService:
        return 'TV';
      default:
        return provider.isEmpty ? '·' : provider.substring(0, 1).toUpperCase();
    }
  }

  /// Show the Pipeline play loader, wired to this provider. [bound] uses the
  /// short (prepare → start) checklist; otherwise it's the full search flow.
  static PipelineLoadingOverlay _showPipeline(
    BuildContext context, {
    required String provider,
    required PlaybackMeta? meta,
    required String title,
    bool bound = false,
    VoidCallback? onCancel,
  }) {
    final sub = (meta != null && meta.season != null && meta.episode != null)
        ? _seLabel(meta.season!, meta.episode!)
        : null;
    final app = AppThemeScope.of(context);
    return PipelineLoadingOverlay.show(
      context,
      posterUrl: meta?.posterUrl,
      title: title,
      subtitle: sub,
      providerLabel: _label(provider),
      providerCode: _providerCode(provider),
      providerColor: _providerGradient(provider).first,
      bound: bound,
      hasCacheCheck: provider == 'torbox' || provider == 'premiumize',
      // The loader is a dark cinematic plate on every theme (black Material,
      // black-at-alpha scrims), so its ink is `onGlass`, never page ink.
      // `inkOnFill` is already contrast-scored against the accent it sits on.
      loaderGround: app.stremioTv.loaderGround,
      loaderAccent: app.stremioTv.loaderAccent,
      loaderAccent2: app.stremioTv.loaderAccent2,
      railFar: app.stremioTv.loaderRailFar,
      ink: app.onGlass,
      inkOnFill: app.stremioTv.inkOnFill,
      // Settings → Appearance → Play Loader. Read from the synchronous mirror:
      // a play cannot await a preference, and the mirror's default IS the
      // stored default, so an unwarmed read only ever mis-serves someone who
      // explicitly chose Classic.
      style:
          PlayLoaderStyleController.cached == PlayLoaderStyleController.classic
          ? PlayLoaderStyle.classic
          : PlayLoaderStyle.marquee,
      art: meta?.art,
      onCancel: onCancel,
    );
  }

  /// Immediate feedback while Quick Play resolves preferences, resume data,
  /// and pinned sources before the provider-specific pipeline can begin.
  static PipelineLoadingOverlay showResolvingOverlay(
    BuildContext context, {
    required PlaybackMeta? meta,
    required String title,
    VoidCallback? onCancel,
  }) => _showPipeline(
    context,
    provider: 'preparing',
    meta: meta,
    title: title,
    onCancel: onCancel,
  );

  // ── Minimal UI feedback ────────────────────────────────────────────────────

  /// The app's shared cinematic add-loading overlay (not a plain spinner box).
  static DebridLoadingHandle _showLoading(
    BuildContext context,
    String provider,
    String name,
  ) {
    switch (provider) {
      case 'debrid':
        return DebridLoadingOverlay.showRealDebrid(context, name);
      case 'torbox':
        return DebridLoadingOverlay.showTorbox(context, name);
      case 'premiumize':
        return DebridLoadingOverlay.showPremiumize(context, name);
      case 'alldebrid':
        return DebridLoadingOverlay.showAllDebrid(context, name);
      case 'pikpak':
        return DebridLoadingOverlay.show(
          context,
          provider: 'PikPak',
          torrentName: name,
          accentColor: const Color(0xFF6366F1),
          icon: Icons.cloud_circle_rounded,
        );
      default:
        return DebridLoadingOverlay.show(
          context,
          provider: _label(provider),
          torrentName: name,
        );
    }
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  static int directValidationBudgetForRules(QuickPlayRules? rules) => SourceCandidateRanking.directValidationBudgetForRules(rules);
  static bool shouldPreflightDirectStream(Torrent torrent) => SourceCandidateRanking.shouldPreflightDirectStream(torrent);

  static Future<FilterLadder> loadLadder({bool includeSize = true, QuickPlayRules? rules}) => SourceFilterLadder.loadLadder(includeSize: includeSize, rules: rules);

  static SeriesSourceFetcher? seriesFetcherFor({required PlaybackMeta? meta, String? provider, bool packsFetched = false, bool episodesFetched = false, Future<List<Torrent>>? initialEpisodeSearch}) => SourceSeriesFetcher.seriesFetcherFor(meta: meta, provider: provider, packsFetched: packsFetched, episodesFetched: episodesFetched, initialEpisodeSearch: initialEpisodeSearch);
  static Future<List<Torrent>> prepareRecoverySources(List<Torrent> raw, {required QuickPlayRules rules, required String? provider, required FilterLadder ladder, Future<List<Torrent>> Function(String, List<Torrent>)? cacheCheck}) => RecoverySourceResolution.prepareRecoverySources(raw, rules: rules, provider: provider, ladder: ladder, cacheCheck: cacheCheck);
  static Future<List<PlaylistEntry>?> resolveRecoverySource(Torrent source, {required String? provider, AutomaticSourceBindings? sourceBindings, ProfileSessionOwner? owner, bool Function()? canContinue, int? season, int? episode}) => RecoverySourceResolution.resolveRecoverySource(source, provider: provider, sourceBindings: sourceBindings, owner: owner, canContinue: canContinue, season: season, episode: episode);
}
