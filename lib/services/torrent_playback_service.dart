import 'package:debrify/services/storage/quick_play_policy_prefs.dart';
import 'package:debrify/services/storage/playback_progress_store.dart';
import 'package:debrify/services/storage/provider_credential_prefs.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../models/playlist_view_mode.dart';
import '../models/profiles/profile_policy.dart';
import '../models/quick_play_rules.dart';
import '../models/torrent.dart';
import '../models/playlist_entry.dart';
import '../theme/app_theme_scope.dart';
import '../utils/deovr_utils.dart' as deovr;
import '../utils/dialog_tap_guard.dart';
import '../utils/filter_ladder.dart';
import '../utils/file_utils.dart';
import '../utils/formatters.dart';
import '../utils/series_parser.dart';
import '../utils/torrent_coverage_detector.dart';
import '../widgets/debrid_action_sheet.dart';
import '../widgets/debrid_loading_overlay.dart';
import '../widgets/not_cached_dialog.dart';
import '../widgets/pipeline_loading_overlay.dart';
import '../widgets/provider_picker_dialog.dart';
import 'alldebrid_service.dart';
import 'cloud/cloud_credentials.dart';
import 'cloud/cloud_exceptions.dart';
import 'cloud/cloud_playback_helpers.dart';
import 'cloud/cloud_playback_result.dart';
import 'cloud/cloud_playlist_payload.dart';
import 'cloud/cloud_provider_id.dart';
import 'cloud/cloud_provider_presentation.dart';
import 'cloud/cloud_provider_registry.dart';
import 'cloud/pack_negative_cache.dart';
import 'cloud/playback_cache_first.dart';
import 'debrid_service.dart';
import 'playback_service_dispatch.dart';
import 'debrify_tv_channel_add_service.dart';
import 'download_service.dart';
import 'local_bound_source_service.dart';
import 'local_playback_resume_resolver.dart';
import 'pikpak_api_service.dart';
import 'play_loader_style.dart';
import 'profiles/profile_policy_guard.dart';
import 'series_source_fetcher.dart';
import 'stremio_service.dart';
import 'series_source_service.dart';
import 'storage_service.dart';
import 'stream_url_validator.dart';
import 'torrent_file_service.dart';
import 'torrent_service.dart';
import 'video_player_launcher.dart';
import 'torrent_playback/playback_meta.dart';
export 'torrent_playback/playback_meta.dart';
import 'torrent_playback/playback_candidate_ranking.dart';
import 'torrent_playback/playback_provider_resolution.dart';
import 'torrent_playback/playback_source_fetchers.dart';
import 'torrent_playback/playback_source_search.dart';

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

  /// Distinguishes "user dismissed the provider picker" (silent) from
  /// "no provider configured" (null → prompt to add one in Settings).
  static const String _cancelled = '__cancelled__';

  // ── Moved to lib/services/torrent_playback/ ────────────────────────────────
  // The two "Load more sources" factories now live in PlaybackSourceFetchers.
  // These constant tear-offs exist ONLY because
  // test/playback_provider_resolution_origin_pin_test.dart,
  // test/playback_source_search_origin_pin_test.dart and
  // test/quick_play_rules_test.dart still address them through this class and
  // must keep passing unedited across the move. Retained as closeout debt; no
  // lib caller depends on them.
  @visibleForTesting
  static const seriesFetcherFor = PlaybackSourceFetchers.seriesFetcherFor;
  @visibleForTesting
  static const movieFetcherFor = PlaybackSourceFetchers.movieFetcherFor;

  static bool _recentlyNoPack(
    String imdbId,
    int season,
    String provider,
    QuickPlayRules rules,
  ) => PackNegativeCache.instance.recentlyNoPack(
    imdbId,
    season,
    provider,
    rules,
  );

  static void _markNoPack(
    String imdbId,
    int season,
    String provider,
    QuickPlayRules rules,
    Duration ttl,
  ) => PackNegativeCache.instance.markNoPack(
    imdbId,
    season,
    provider,
    rules,
    ttl,
  );

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
  }) async {
    // Direct-URL addon streams bypass debrid entirely. Content metadata and
    // the in-player Sources switcher ride along (matching Home's
    // _playDirectStream) so series streams get Continue Watching, subtitles,
    // source switching, and the Next Episode hand-back. No provider is
    // involved, so the advance goes bound-sources → addon-stream flow.
    if (torrent.streamType == StreamType.directUrl &&
        (torrent.directUrl?.isNotEmpty ?? false)) {
      final resolverProvider =
          await PlaybackProviderResolution.defaultConfiguredProvider();
      if (!context.mounted) return;
      final fetcher = meta?.contentType == 'movie'
          ? PlaybackSourceFetchers.movieFetcherFor(meta: meta)
          : PlaybackSourceFetchers.seriesFetcherFor(
              meta: meta,
              episodesFetched: sources != null,
            );
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
      await VideoPlayerLauncher.push(
        context,
        _playerArgs(
          videoUrl: torrent.directUrl!,
          title: torrent.displayTitle,
          subtitle: torrent.source.isNotEmpty ? torrent.source : null,
          stremioSources: launchSources,
          stremioCurrentSourceIndex: launchSourceIndex,
          resolveSourceToPlaylist: (launchSources.length > 1 || fetcher != null)
              ? _lazyProviderResolver()
              : null,
          startupFailoverEnabled: true,
          startupResolverProvider: resolverProvider,
          onStremioSourceCommitted: _validatedLaunchCommitter(
            resolverProvider ?? SeriesSource.addonDirectService,
            meta,
          ),
          seriesSourceFetcher: fetcher,
          meta: meta,
        ),
        onQuickPlayNextEpisode: _nextEpisodeHandlerFor(context, meta),
      );
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
      if (!context.mounted) return;
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
        if (context.mounted) _snack(context, 'Could not open link: $e');
      }
      return;
    }

    final provider = await _pickProvider(context);
    if (!context.mounted) return;
    if (provider == _cancelled) return; // user dismissed the picker
    if (provider == null) {
      _snack(context, 'No debrid provider configured. Add one in Settings.');
      return;
    }
    final magnet = await _magnetFor(torrent);
    if (!context.mounted) return;
    if (magnet == null) {
      _snack(context, 'This result has no magnet or infohash to play.');
      return;
    }
    final action = forcePlay ? 'play' : await _postAction(provider);
    if (!context.mounted) return;

    final rootNav = Navigator.of(context, rootNavigator: true);
    _showLoading(context, provider, torrent.displayTitle);
    _Resolved? resolved;
    Object? notCached;
    try {
      resolved = await _add(provider, magnet, torrent);
    } on TorrentNotCachedException catch (e) {
      notCached = e;
    } on AllDebridTorrentNotReadyException catch (e) {
      notCached = e;
    } on TorboxNotCached catch (e) {
      notCached = e;
    } on PremiumizeNotCached catch (e) {
      notCached = e;
    } on PikPakStillProcessing {
      if (rootNav.canPop()) rootNav.pop();
      if (context.mounted) {
        _snack(
          context,
          'Files still processing on PikPak. Check the PikPak Files page later.',
        );
      }
      return;
    } on PikPakFailed {
      if (rootNav.canPop()) rootNav.pop();
      if (context.mounted) _snack(context, 'Download failed on PikPak.');
      return;
    } catch (e) {
      if (rootNav.canPop()) rootNav.pop();
      if (context.mounted) _snack(context, 'Could not resolve source: $e');
      return;
    }
    if (rootNav.canPop()) rootNav.pop();
    if (!context.mounted) return;

    if (notCached != null) {
      await _handleNotCached(context, notCached, provider, magnet);
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
          if (context.mounted) {
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
        await _download(context, resolved, torrent, provider);
        break;
      case 'playlist':
        await _addToPlaylist(context, resolved, torrent, provider, meta: meta);
        break;
      case 'channel':
        // Saved "Add to channel" action (parity with the old screen): cache the
        // torrent into a Debrify TV channel instead of playing it. Without this
        // case the switch fell through to `default` and silently played.
        await DebrifyTvChannelAddService.addTorrentsToChannel(
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
  }) async {
    if (rules != null) {
      torrents = PlaybackCandidateRanking.orderCandidatesForRules(
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

    bool cancelled() => isCancelled?.call() ?? false;

    // Plays a direct-URL addon stream instantly (no debrid needed). Content
    // metadata and the Sources switcher ride along (matching Home's
    // _playDirectStream) so series streams get Continue Watching, subtitles,
    // source switching, and the Next Episode hand-back. The advance reuses
    // [provider] when the caller resolved one (torrent chain); otherwise it
    // stays on the bound-sources → addon-stream path this play came from.
    Future<void> playDirect(Torrent direct) async {
      // The loader (when one is up) stays through the launch prep; the
      // launcher dismisses it the moment the player takes the screen, and
      // guarantees the dismissal on failure so it can never linger. The
      // finally only covers a throw BEFORE push() takes the callback (args
      // built up front for exactly that reason) — after which the launcher
      // owns the dismissal.
      final loader = ov;
      var handedToLauncher = false;
      try {
        final resolverProvider =
            provider ??
            await PlaybackProviderResolution.defaultConfiguredProvider();
        if (!context.mounted) return;
        final args = _playerArgs(
          videoUrl: direct.directUrl!,
          title: direct.displayTitle,
          subtitle: direct.source.isNotEmpty ? direct.source : null,
          stremioSources: torrents,
          stremioCurrentSourceIndex: torrents.indexOf(direct),
          resolveSourceToPlaylist:
              (torrents.length > 1 || seriesFetcher != null)
              ? (resolverProvider == null
                    ? _lazyProviderResolver()
                    : _resolverFor(resolverProvider))
              : null,
          startupFailoverEnabled: true,
          startupResolverProvider: resolverProvider,
          onStremioSourceCommitted: _validatedLaunchCommitter(
            resolverProvider ?? SeriesSource.addonDirectService,
            meta,
          ),
          seriesSourceFetcher: seriesFetcher,
          meta: meta,
        );
        final nextEpisodeHandler = _nextEpisodeHandlerFor(
          context,
          meta,
          provider: provider,
        );
        handedToLauncher = loader != null;
        await VideoPlayerLauncher.push(
          context,
          args,
          onPlayerHandoff: loader?.dismiss,
          onQuickPlayNextEpisode: nextEpisodeHandler,
        );
      } finally {
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
    var validationBudget = PlaybackCandidateRanking.directValidationBudgetForRules(rules);
    Future<bool> directLooksAlive(Torrent t) async {
      if (rules?.validateDirectLinks == false) return true;
      if (!validatableVod) return true;
      // AIOStreams/debrid proxy URLs can be single-use or bind themselves to
      // the address family of the first request. Probing one through Dart's
      // HTTP stack and then opening it through media-kit/ExoPlayer can turn a
      // healthy link into a provider-generated "Wrong IP" slate (IPv6 HEAD,
      // IPv4 playback). These URLs must be opened first by the real player;
      // its startup gate owns failure detection and candidate failover.
      if (!PlaybackCandidateRanking.shouldPreflightDirectStream(t)) {
        debugPrint(
          '[StartupFailover] event=preflight_bypass platform=flutter '
          'reason=ip_bound_addon addon=${t.stremioAddonId ?? '-'}',
        );
        return true;
      }
      final url = t.directUrl!;
      if (deadDirectUrls.contains(url)) {
        debugPrint(
          '[StartupFailover] event=preflight_result platform=flutter '
          'ok=false reason=known_dead',
        );
        return false;
      }
      if (validationBudget <= 0) {
        debugPrint(
          '[StartupFailover] event=preflight_bypass platform=flutter '
          'reason=budget_exhausted',
        );
        return true; // budget spent — trust it
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
      );
      debugPrint(
        '[StartupFailover] event=preflight_result platform=flutter '
        'ok=$alive remainingBudget=$validationBudget',
      );
      if (!alive) {
        deadDirectUrls.add(url);
        ov?.setNote('Skipped a dead stream link — trying the next source…');
      }
      return alive;
    }

    // Walks every direct stream in (tier-ordered) list order and plays the
    // first one that validates. Returns true when it handled the play (or the
    // user cancelled mid-walk); false when no direct stream survived.
    Future<bool> playFirstAliveDirect() async {
      for (final t in torrents) {
        final isDirect =
            t.streamType == StreamType.directUrl &&
            (t.directUrl?.isNotEmpty ?? false);
        if (!isDirect) continue;
        if (cancelled()) return true; // overlay dismissed by the Cancel tap
        if (await directLooksAlive(t)) {
          if (cancelled()) return true;
          await playDirect(t);
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
        final isDirect =
            source.streamType == StreamType.directUrl &&
            (source.directUrl?.isNotEmpty ?? false);
        final isTorrent = PlaybackCandidateRanking.hasAcquisition(source);
        if (!isDirect && !isTorrent) continue;

        if (isDirect) {
          if (await directLooksAlive(source)) {
            if (cancelled()) return;
            await playDirect(source);
            return;
          }
          continue;
        }

        if (!context.mounted) {
          if (ov != null) closeLoading();
          return;
        }
        if (!providerWasChecked) {
          strictProvider = await _pickProvider(context);
          providerWasChecked = true;
          providerUnavailable = strictProvider == null;
        }
        if (!context.mounted) {
          if (ov != null) closeLoading();
          return;
        }
        if (strictProvider == _cancelled) {
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
                (t) =>
                    t.streamType == StreamType.torrent &&
                    PlaybackCandidateRanking.hasAcquisition(t),
              )
              .toList();
          if (PlaybackServiceDispatch.hasCacheCheck(strictProvider)) {
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
            preparedTorrents = await _cacheFirst(
              strictProvider,
              preparedTorrents,
            );
            preparedTorrents = PlaybackCandidateRanking.orderCacheCheckedCandidatesForRules(
              preparedTorrents,
              rules: rules,
              ladder: ladder,
            );
            if (!context.mounted) {
              closeLoading();
              return;
            }
            if (cancelled()) return;
          }
          if (tiered) {
            final (safeTorrents, safeAttempts) = PlaybackCandidateRanking.packTopSafety(
              preparedTorrents,
              provider: strictProvider,
              ladder: ladder,
              season: meta?.season,
              episode: meta?.episode,
            );
            preparedTorrents = safeTorrents;
            if (safeAttempts > limit) limit = safeAttempts;
          }
          exactSources = PlaybackCandidateRanking.mergePreparedTorrentOrder(
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
        if (PlaybackServiceDispatch.oneProbeSafety(strictProvider) && pikPakTorrentProbed) continue;
        attempts++;
        if (PlaybackServiceDispatch.oneProbeSafety(strictProvider)) pikPakTorrentProbed = true;
        ov ??= _showPipeline(
          context,
          provider: strictProvider,
          meta: meta,
          title: title ?? source.displayTitle,
        );
        ov.setStage(PlayLoadStage.preparing);
        final (resolved, winner) = await _probeCandidates(
          strictProvider,
          [source],
          season: meta?.season,
          episode: meta?.episode,
          rules: rules.copyWith(tryNextOnFailure: false, maxAttempts: 1),
          isCancelled: cancelled,
        );
        if (!context.mounted) {
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
    if (PlaybackCandidateRanking.shouldTryDirectBeforeTorrent(rules)) {
      var selectable = torrents;
      var direct = PlaybackCandidateRanking.selectDirect(selectable, ladder).$1;
      while (direct != null) {
        if (cancelled()) return; // e.g. Cancel during a caller's await
        if (await directLooksAlive(direct)) {
          if (cancelled()) return;
          await playDirect(direct);
          return;
        }
        final dead = direct;
        selectable = selectable.where((t) => !identical(t, dead)).toList();
        direct = PlaybackCandidateRanking.selectDirect(selectable, ladder).$1;
      }
    }

    // Every direct link VALIDATED dead and nothing probeable exists: a
    // provider prompt (or "no provider" snack) would be nonsense — the play
    // failed because the stream links are down, say so. Budget-exhausted
    // directs are NOT in the dead set, so when unvalidated candidates remain
    // this can't fire and the trust-play rescue below still runs.
    if (deadDirectUrls.isNotEmpty &&
        !torrents.any(
          (t) =>
              t.streamType != StreamType.externalUrl &&
              PlaybackCandidateRanking.hasAcquisition(t),
        ) &&
        !torrents.any(
          (t) =>
              t.streamType == StreamType.directUrl &&
              (t.directUrl?.isNotEmpty ?? false) &&
              !deadDirectUrls.contains(t.directUrl),
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

    final prov = provider ?? await _pickProvider(context);
    // These bail-outs are reachable when the caller passed no provider (the
    // non-IMDb addon-stream path with only torrent results). Dismiss the
    // caller's overlay on each, or it stays stuck full-screen (both overlays
    // are non-dismissable by the system back button).
    if (!context.mounted) {
      if (ov != null) closeLoading();
      return;
    }
    if (prov == _cancelled) {
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
          (t) =>
              t.streamType != StreamType.externalUrl &&
              PlaybackCandidateRanking.hasAcquisition(t),
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
    if (PlaybackServiceDispatch.hasCacheCheck(prov)) {
      loader.setStage(PlayLoadStage.cacheCheck);
      candidates = await _cacheFirst(prov, candidates);
      // One cache call for the whole list, then a stable tier re-sort:
      // filters dominate cachedness, cached-first survives WITHIN each tier
      // (plan §3.4, "cache-first demoted to within-tier").
      if (rules != null) {
        candidates = PlaybackCandidateRanking.orderCacheCheckedCandidatesForRules(
          candidates,
          rules: rules,
          ladder: ladder,
        );
      } else if (tiered) {
        candidates = ladder.order(candidates);
      }
      if (!context.mounted) {
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
      final (safeList, safeAttempts) = PlaybackCandidateRanking.packTopSafety(
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
    final (res, winner) = await _probeCandidates(
      prov,
      candidates,
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
    if (!context.mounted) {
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
    );
  }

  /// Probe [candidates] in order on [prov] until one resolves to an instantly
  /// playable URL — and, when [season]/[episode] are both set, actually
  /// contains that episode (a pack that resolved fine but lacks the episode is
  /// skipped and its fresh RD/PikPak entry deleted, matching _playViaBound).
  /// Honors the Quick-Play retry settings: PikPak probes only the top
  /// candidate (each probe queues a real download we can't cheaply clean up);
  /// others try one candidate, or up to the configured max when "try multiple
  /// torrents" is on. Returns the resolution and the winning torrent, or
  /// (null, null) on failure/cancel.
  static Future<(_Resolved?, Torrent?)> _probeCandidates(
    String prov,
    List<Torrent> candidates, {
    int? season,
    int? episode,
    QuickPlayRules? rules,
    bool Function()? isCancelled,
    // Floor on attempts (the ladder's pack-top safety). PikPak stays at 1 —
    // every probe there queues a real download that can't be cheaply undone.
    int minAttempts = 1,
    // Called as each candidate is about to be probed (ladder narration).
    void Function(Torrent t)? onCandidate,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;
    final tryMultiple =
        rules?.tryNextOnFailure ??
        await QuickPlayPolicyPrefs.getQuickPlayTryMultipleTorrents();
    final maxRetries =
        rules?.maxAttempts ?? await QuickPlayPolicyPrefs.getQuickPlayMaxRetries();
    final maxAttempts = PlaybackCandidateRanking.probeAttemptCount(
      prov,
      tryMultiple: tryMultiple,
      maxRetries: maxRetries,
      minAttempts: minAttempts,
    );
    for (final t in candidates.take(maxAttempts)) {
      if (cancelled()) return (null, null);
      onCandidate?.call(t);
      try {
        final magnet = await _magnetFor(t);
        if (magnet == null) continue;
        if (cancelled()) return (null, null);
        final r = await _add(prov, magnet, t);
        if (r.playUrl != null && r.playUrl!.isNotEmpty) {
          // For a series episode, don't accept a pack that resolved fine but
          // doesn't actually contain the requested episode (mislabeled or
          // wrong-season result) — mirror _playViaBound instead of letting the
          // player silently start the wrong/first episode. Keep probing the
          // remaining candidates for one that genuinely has it.
          if (season != null &&
              episode != null &&
              !_resolvedHasEpisode(r, season, episode)) {
            // Delete the fresh RD/PikPak entry this probe created so skips
            // don't pile up orphans (TorBox/AllDebrid dedup the add; Premiumize
            // adds nothing), matching _playViaBound's cleanup.
            if (PlaybackServiceDispatch.deletesRdOrphan(prov) && (r.rdTorrentId?.isNotEmpty ?? false)) {
              try {
                final apiKey = (await StorageService.getApiKey()) ?? '';
                await DebridService.deleteTorrent(apiKey, r.rdTorrentId!);
              } catch (_) {}
            } else if (PlaybackServiceDispatch.deletesPikPakOrphan(prov) &&
                (r.pikpakFileId?.isNotEmpty ?? false)) {
              try {
                await PikPakApiService.instance.batchDeleteFiles([
                  r.pikpakFileId!,
                ]);
              } catch (_) {}
            }
            continue;
          }
          return (r, t);
        }
      } on TorrentNotCachedException catch (e) {
        // Probed torrent is downloading — remove it so RD stays clean.
        try {
          await DebridService.deleteTorrent(e.apiKey, e.torrentId);
        } catch (_) {}
      } on AllDebridTorrentNotReadyException catch (e) {
        try {
          await AllDebridService.deleteMagnet(e.apiKey, e.magnetId);
        } catch (_) {}
      } catch (_) {
        // TorboxNotCached / PremiumizeNotCached / transient — try next.
      }
    }
    return (null, null);
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
    // "Play button opens" preference (see [QuickPlayPolicyPrefs.getPlayButtonMode]):
    // only a real Play press passes an opener, so binge auto-advance and
    // post-failure recovery keep their existing no-prompt contract for free.
    VoidCallback? openSourcePicker,
  }) async {
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
      rules = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: isMovie);
      if (openSourcePicker != null) {
        playMode = await QuickPlayPolicyPrefs.getPlayButtonMode();
      }
      if (rules.sourcePriority.isNotEmpty) {
        await PlaybackCandidateRanking.warmSourceAliases();
      }
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
    if (!context.mounted || cancelled) {
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
      if (!PlaybackCandidateRanking.allowsAddonSearch(rules)) {
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
      );
      return;
    }

    // Bound-source reuse: if the user pinned a source for this title, play it
    // directly and skip the torrent search entirely. A series binding is only
    // usable when a concrete season+episode is requested (to land in the pack).
    if (!skipBound) {
      late final List<SeriesSource> bound;
      try {
        bound = await SeriesSourceService.getSources(imdbId);
      } catch (_) {
        resolving.dismiss();
        rethrow;
      }
      if (!context.mounted || cancelled) {
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
        );
        if (played) return;
        if (!context.mounted) return;
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

    // Addon-leading, exact-episode routes search addons before asking the user
    // to choose a debrid provider. Direct addon links need no provider at all;
    // addon torrents still trigger the picker lazily inside playBest. Series
    // pack-first routes keep their existing provider-first contract because a
    // reusable torrent pack must be cache-probed before an episode fallback.
    var addonFallbackAlreadySearched = false;
    if (PlaybackCandidateRanking.shouldSearchAddonsBeforeProvider(
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
      );
      if (!context.mounted || handled) return;
      addonFallbackAlreadySearched = true;
      // The addon stage has already completed empty. Continue with only the
      // engine half instead of querying the same addons a second time.
      activeRules = rules.copyWith(
        sourceMode: QuickPlaySourceMode.torrentsOnly,
        preserveLegacyCombinedPackSearch: false,
      );
    }

    resolving.dismiss();
    final provider = preferredProvider ?? await _pickProvider(context);
    if (!context.mounted) return;
    if (provider == _cancelled) return;
    if (provider == null) {
      if (addonFallbackAlreadySearched) {
        _snack(
          context,
          'No direct stream for "$label". Add a debrid provider in Settings for more sources.',
        );
        return;
      }
      if (!PlaybackCandidateRanking.allowsAddonSearch(activeRules)) {
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
      );
      return;
    }
    // The Pipeline loader spans search → cache-check → prepare → start; its
    // checklist advances via setStage as this flow progresses.
    final cancel = _PlaybackCancelToken();
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
    final ladder = await PlaybackCandidateRanking.loadLadder(includeSize: isMovie, rules: activeRules);
    if (cancel.cancelled) return; // Cancel during the prefs read
    if (!context.mounted) {
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
      final packResult = await PlaybackSourceSearch.searchSeriesPackSources(
        imdbId: imdbId,
        label: label,
        season: season!,
        provider: provider,
        ladder: ladder,
        rules: activeRules,
        isCancelled: () => cancel.cancelled,
        onCacheCheck: () => overlay.setStage(PlayLoadStage.cacheCheck),
      );
      final searchOk = packResult != null;
      final packs = packResult ?? const <Torrent>[];
      if (cancel.cancelled) return null;
      if (!context.mounted) {
        closeLoading();
        return null;
      }
      _applyLadderNote(overlay, ladder, packs);
      if (cancel.cancelled) return null;
      if (!context.mounted) {
        closeLoading();
        return null;
      }
      if (packs.isNotEmpty) {
        overlay.setStage(PlayLoadStage.preparing);
        final (packResolved, packWinner) = await _probeCandidates(
          provider,
          packs,
          season: season,
          episode: episode,
          rules: activeRules,
          isCancelled: () => cancel.cancelled,
        );
        if (cancel.cancelled) return null;
        if (!context.mounted) {
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
            seriesFetcher: PlaybackSourceFetchers.seriesFetcherFor(
              meta: meta,
              provider: provider,
              packsFetched: true,
            ),
            overlay: overlay,
            startupFailoverEnabled: true,
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
        season != null &&
        episode != null &&
        !PlaybackServiceDispatch.skipSeriesTorrentPin(provider) &&
        !_recentlyNoPack(imdbId, season, provider, activeRules) &&
        activeRules.packPreference != QuickPlayPackPreference.exactEpisodeOnly;

    if (packRouteAllowed && activeRules.preferSeriesPacks) {
      final packed = await tryPackRoute();
      if (packed != false) return;
    }

    List<Torrent> torrents;
    try {
      torrents = await PlaybackSourceSearch.searchCuratedSources(
        imdbId: imdbId,
        label: label,
        isMovie: isMovie,
        season: season,
        episode: episode,
        provider: provider,
        rules: activeRules,
        isCancelled: () => cancel.cancelled,
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
    if (!context.mounted) {
      closeLoading();
      return;
    }
    if (torrents.isEmpty) {
      // Episode-first route (Prefer season packs off): packs are the
      // FALLBACK when the episode search comes up dry, so a show that only
      // exists as packs still plays.
      if (packRouteAllowed && !activeRules.preferSeriesPacks) {
        final packed = await tryPackRoute();
        if (packed != false) return;
      }
      closeLoading();
      _snack(context, 'No sources found for "$label".');
      return;
    }

    // Rank by filter strictness (stable — curation's relevance order survives
    // within each tier) and narrate the outcome on the loader. The pack-top
    // safety (§3.4b.3) lives inside playBest, AFTER its final re-sorts.
    torrents = PlaybackCandidateRanking.orderCandidatesForRules(
      torrents,
      rules: activeRules,
      ladder: ladder,
    );
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
      isCancelled: () => cancel.cancelled,
      ladder: ladder,
      rules: activeRules,
      // The dedicated episode fetch just ran; the pack tab stays fetchable
      // even when the pack-first search ran earlier — its results were
      // discarded (nothing instantly playable), so "Load more" re-lists
      // them for a manual pick.
      seriesFetcher: PlaybackSourceFetchers.seriesFetcherFor(
        meta: meta,
        provider: provider,
        episodesFetched: true,
      ),
    );
  }

  static void _applyLadderNote(
    PipelineLoadingOverlay overlay,
    FilterLadder ladder,
    List<Torrent> ordered,
  ) {
    final note = PlaybackCandidateRanking.ladderNote(ladder, ordered);
    if (note != null) overlay.setNote(note);
  }

  /// Play non-IMDb catalog content (IPTV / TV channels) straight from the
  /// addon's own stream endpoint — no torrent engine, no debrid provider. Shows
  /// the same cinematic overlay as [playFromSelection] and hands the resolved
  /// streams to [playBest], which plays a direct stream instantly.
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
  }) async {
    final cancel = _PlaybackCancelToken();
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
          );
        case QuickPlaySourceMode.torrentsThenAddons:
        case QuickPlaySourceMode.addonsThenTorrents:
          throw StateError('Fallback source modes must be expanded first');
      }
    }

    Future<Map<String, dynamic>> search() async {
      final torrents = <Torrent>[];
      final engineErrors = <String, String>{};
      final addonErrors = <String, String>{};
      for (final stage in PlaybackCandidateRanking.addonStreamSearchPlan(
        rules,
        noProvider: noProvider,
        forceAddonOnly: forceAddonOnly,
      )) {
        final result = await query(stage);
        final stageTorrents = (result['torrents'] as List).cast<Torrent>();
        torrents.addAll(stageTorrents);
        engineErrors.addAll(
          (result['engineErrors'] as Map?)?.cast<String, String>() ?? const {},
        );
        addonErrors.addAll(
          (result['addonErrors'] as Map?)?.cast<String, String>() ?? const {},
        );
        // Forced/no-provider searches are addon-only; mixed provider searches
        // are a single combined stage. Keep this guard for explicit one-stage
        // legacy modes and to avoid unnecessary future stages if added.
        final foundUsable = stageTorrents.any(
          (torrent) =>
              (rules.allowDirectLinks ||
                  torrent.streamType != StreamType.directUrl) &&
              PlaybackCandidateRanking.isAutoPlayableCandidate(torrent),
        );
        if (foundUsable) break;
      }
      return {
        'torrents': torrents,
        'engineErrors': engineErrors,
        'addonErrors': addonErrors,
      };
    }

    Map<String, dynamic> res;
    try {
      res = await search();
    } catch (e) {
      if (cancel.cancelled) return true;
      closeLoading();
      if (fallbackWhenEmpty) return false;
      if (context.mounted) _snack(context, 'Search failed: $e');
      return true;
    }
    if (cancel.cancelled) return true;
    if (!context.mounted) {
      closeLoading();
      return true;
    }
    // Addon errors ride along keyed 'stremio:<addon name>' (timeouts and
    // upstream 5xx land here, not as a thrown exception). The two searches
    // surface them under different keys: searchByImdbWithStremio folds addon +
    // engine errors together under 'engineErrors', while the noProvider path's
    // searchStremioAddonsOnly returns them raw under 'addonErrors'. Read both,
    // then keep only 'stremio:' keys — a flaky engine must not misblame
    // "didn't respond" on a title that simply has no stream.
    Map<String, String> addonErrorsOf(Map<String, dynamic> r) {
      final all = <String, String>{
        ...?(r['engineErrors'] as Map<String, String>?),
        ...?(r['addonErrors'] as Map<String, String>?),
      };
      return {
        for (final e in all.entries)
          if (e.key.startsWith('stremio:')) e.key: e.value,
      };
    }

    var torrents = (res['torrents'] as List).cast<Torrent>();
    var errors = addonErrorsOf(res);
    // Empty ONLY because an addon errored is usually a transient upstream
    // blip — retry once before giving up.
    if (torrents.isEmpty && errors.isNotEmpty) {
      try {
        res = await search();
        torrents = (res['torrents'] as List).cast<Torrent>();
        errors = addonErrorsOf(res);
      } catch (_) {
        // Keep the first attempt's (empty) result — reported below.
      }
      if (cancel.cancelled) return true;
      if (!context.mounted) {
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
        final failed = errors.keys
            .map((k) => k.replaceFirst('stremio:', ''))
            .join(', ');
        _snack(context, '$failed didn\'t respond for "$label" — try again.');
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
    // Same filter ladder as the torrent path — addon streams rank by how
    // well their labels match the saved filters. Size is movie-only.
    final ladder = await PlaybackCandidateRanking.loadLadder(includeSize: isMovie, rules: rules);
    if (cancel.cancelled) return true; // Cancel during the prefs read
    if (!context.mounted) {
      closeLoading();
      return true;
    }
    torrents = PlaybackCandidateRanking.orderCandidatesForRules(torrents, rules: rules, ladder: ladder);
    if (fallbackWhenEmpty && !torrents.any(PlaybackCandidateRanking.isAutoPlayableCandidate)) {
      closeLoading();
      return false;
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
          ? PlaybackSourceFetchers.movieFetcherFor(meta: meta)
          : PlaybackSourceFetchers.seriesFetcherFor(
              meta: meta,
              episodesFetched: true,
            ),
    );
    return true;
  }

  /// Real-Debrid is `'rd'` in [SeriesSource] (Home's convention, shared
  /// storage) but `'debrid'` as this service's provider key. Map between them so
  /// bindings created in Home replay here and vice-versa.
  static String _providerFromStored(String stored) =>
      PlaybackServiceDispatch.providerFromStored(stored);
  static String storedProviderKey(String provider) =>
      PlaybackServiceDispatch.storedProviderKey(provider);

  /// Providers whose bound sources this isolated engine can replay — the five
  /// debrid providers plus 'local' (on-device file/folder).
  static bool _boundProviderSupported(String stored) =>
      PlaybackServiceDispatch.boundProviderSupported(stored);

  /// Resolve a 'local' bound source (on-device movie file or series folder) into
  /// a playable [_Resolved]. Self-heals (removes) a source whose file/folder is
  /// gone. Returns (null, hint) when unavailable so the caller falls back to
  /// search — the hint (may be null) says why, using Home's exact wording.
  static Future<(_Resolved?, String?)> _resolveLocalBound(
    String imdbId,
    SeriesSource source,
    PlaybackMeta meta,
  ) async {
    final localPath = (source.localPath?.trim().isNotEmpty ?? false)
        ? source.localPath!.trim()
        : source.debridTorrentId.trim();
    if (localPath.isEmpty) return (null, null);

    final isSeries = meta.contentType == 'series' || source.isLocalSeriesFolder;
    if (isSeries) {
      if (meta.season == null || meta.episode == null) return (null, null);
      if (!await Directory(localPath).exists()) {
        await SeriesSourceService.removeSourceEntry(imdbId, source);
        return (
          null,
          'Saved local folder is no longer available. Falling back to search.',
        );
      }
      final episodes = await LocalBoundSourceService.scanSeriesFolder(
        localPath,
      );
      if (episodes.isEmpty) {
        await SeriesSourceService.removeSourceEntry(imdbId, source);
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
        _Resolved(
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
      await SeriesSourceService.removeSourceEntry(imdbId, source);
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
      _Resolved(
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

  /// Whether the resolved add actually contains [season]/[episode] — the same
  /// SeriesParser filename check Home runs before launching a bound pack
  /// (_findEpisodeInFilenames). Without it, a binding that only covers earlier
  /// seasons still resolves fine and the player silently starts a different
  /// episode (last-played or S1E1) instead of falling back to search.
  ///
  /// Parses BASENAMES only — Home and the player's SeriesPlaylist both parse
  /// the filename, not the folder path; a folder segment like
  /// "Show.S04E01-E10.Pack/" would make this check disagree with the player.
  ///
  /// Errs toward playing: when the resolve exposes no real filename
  /// (single-file RD/PikPak, RAR archives) or nothing in the pack parses to a
  /// season/episode at all (absolute-numbered anime, "Episode 5" naming),
  /// trust the binding and let the player open it — rejecting those would
  /// regress packs that played fine before this check existed.
  /// The (season, episode) of a source whose name is exactly ONE specific
  /// episode, else null. STRICT — returns null for anything that could cover
  /// more than one episode (ranges "S01E01-E10", doubles "S01E01E02",
  /// multiple tokens, or non-singleEpisode coverage) so the [_playViaBound]
  /// cheap-skip below never drops a binding that genuinely contains the
  /// requested episode. When null, the source falls through to the normal
  /// resolve + [_resolvedHasEpisode] check (always correct, just not free).
  static (int, int)? _singleEpisodeOf(String name) {
    final normalized = name.replaceAll(RegExp(r'[._]+'), ' ');
    final matches = RegExp(
      r's(\d{1,2})e(\d{1,3})',
      caseSensitive: false,
    ).allMatches(normalized).toList();
    if (matches.length != 1) return null; // 0, or several distinct episodes
    // Reject anything that could span more than one episode. Kept greedy on
    // purpose: a false positive here just returns null (→ normal resolve,
    // always correct), whereas MISSING a range would wrongly skip a valid
    // multi-episode binding. Covers "E01-E10", "E01 to E10", "E01 & E02",
    // "E01,E02", and the adjacent double "E01E02".
    if (RegExp(
          r'e\d{1,3}\s*(?:-|–|to|thru|through|and|&|,)\s*e?\d{1,3}',
          caseSensitive: false,
        ).hasMatch(normalized) ||
        RegExp(
          r'e\d{1,3}\s*e\d{1,3}',
          caseSensitive: false,
        ).hasMatch(normalized)) {
      return null;
    }
    // Final cross-check against the coverage classifier.
    if (TorrentCoverageDetector.detectCoverage(title: name).coverageType !=
        CoverageType.singleEpisode) {
      return null;
    }
    final m = matches.first;
    final s = int.tryParse(m.group(1)!);
    final e = int.tryParse(m.group(2)!);
    if (s == null || e == null) return null;
    return (s, e);
  }

  static bool _resolvedHasEpisode(_Resolved r, int season, int episode) {
    final List<String> names;
    if (r.playlist != null && r.playlist!.length > 1) {
      names = r.playlist!.map((e) => _fileName(e.title)).toList();
    } else {
      // Single-file resolve: only RD/PikPak leave fileName unset (RD single
      // and RAR resolves carry just the torrent name, which isn't the file).
      final single =
          r.fileName ??
          ((r.playlist?.isNotEmpty ?? false) ? r.playlist!.first.title : null);
      if (single == null) return true; // no filename to judge → play
      names = <String>[_fileName(single)];
    }
    var sawEpisode = false;
    for (final info in SeriesParser.parsePlaylist(names)) {
      if (info.season == null || info.episode == null) continue;
      if (info.season == season && info.episode == episode) return true;
      sawEpisode = true;
    }
    return !sawEpisode;
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
  static Future<_Resolved?> _resolveProviderNativeBound(
    SeriesSource source,
    PlaybackMeta meta,
  ) => CloudProviderRegistry.instance.resolveNativeBound(
    source,
    contentType: meta.contentType,
  );

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
  }) async {
    final usable = sources
        .where((s) => _boundProviderSupported(s.debridService))
        .toList();
    if (usable.isEmpty) return false;

    final firstProv = _providerFromStored(usable.first.debridService);
    final cancel = _PlaybackCancelToken();
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

      // Addon-direct pins store provenance, never the expiring URL. Resolve
      // the current movie/episode endpoint now and launch the freshly returned
      // link. A failed refresh or validation is attempt-scoped: addon,
      // network, and CDN availability do not prove this durable profile is
      // invalid. The loop still skips it for this play, and recovery bypasses
      // bound sources before fresh search, so retaining it cannot loop now.
      if (source.isAddonDirect) {
        fallbackHint =
            'Saved direct source is unavailable. Falling back to search.';
        try {
          final fresh = await StremioService.instance.resolvePinnedDirectStream(
            addonId: source.addonId!,
            addonKey: source.addonKey!,
            streamKey: source.streamKey ?? '',
            streamIndex: source.streamIndex ?? 0,
            type: meta.contentType == 'movie' ? 'movie' : 'series',
            contentId: imdbId,
            season: meta.season,
            episode: meta.episode,
          );
          if (cancel.cancelled) return true;
          final freshUrl = fresh?.directUrl;
          if (fresh != null && freshUrl != null && freshUrl.isNotEmpty) {
            final rules = await QuickPlayPolicyPrefs.getQuickPlayRules(
              isMovie: meta.contentType == 'movie',
            );
            if (cancel.cancelled) return true;
            if (rules.validateDirectLinks &&
                PlaybackCandidateRanking.shouldPreflightDirectStream(fresh)) {
              final minBytes = meta.contentType == 'series'
                  ? 10 * 1024 * 1024
                  : StreamUrlValidator.minContentBytes;
              final alive = await StreamUrlValidator.isPlayableVideoUrl(
                freshUrl,
                minBytes: minBytes,
                lenient: true,
              );
              if (cancel.cancelled) return true;
              if (!alive) {
                continue;
              }
            }
            overlay.setStage(PlayLoadStage.starting);
            if (!context.mounted) {
              closeLoading();
              return false;
            }
            await _launch(
              context,
              _Resolved(
                title: fresh.displayTitle,
                playUrl: freshUrl,
                downloadUrls: [freshUrl],
                fileName: fresh.displayTitle,
              ),
              fresh.displayTitle,
              provider: SeriesSource.addonDirectService,
              meta: meta,
              sources: [fresh],
              sourceIndex: 0,
              seriesFetcher:
                  PlaybackSourceFetchers.seriesFetcherFor(meta: meta) ??
                  PlaybackSourceFetchers.movieFetcherFor(meta: meta),
              overlay: overlay,
              startupFailoverEnabled: true,
              onStartupSourcesExhausted: () => _recoverAfterBoundStartupFailure(
                context,
                imdbId,
                remainingSources,
                label: label,
                meta: meta,
                preferredProvider: preferredProvider,
              ),
            );
            return true;
          }
        } catch (_) {
          // Fail soft and continue through lower-priority pins/search.
        }
        if (!context.mounted) {
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
        final se = _singleEpisodeOf(source.torrentName);
        if (se != null && (se.$1 != season || se.$2 != episode)) {
          continue;
        }
      }

      // Local (on-device file/folder) sources resolve without a debrid add.
      if (source.debridService == SeriesSource.localService) {
        final (r, hint) = await _resolveLocalBound(imdbId, source, meta);
        if (cancel.cancelled) return true;
        if (r != null) {
          overlay.setStage(PlayLoadStage.starting);
          if (!context.mounted) {
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
            meta: meta,
            overlay: overlay,
            startupFailoverEnabled: true,
            onStartupSourcesExhausted: () => _recoverAfterBoundStartupFailure(
              context,
              imdbId,
              remainingSources,
              label: label,
              meta: meta,
              preferredProvider: preferredProvider,
            ),
          );
          return true;
        }
        if (!context.mounted) {
          closeLoading();
          return false;
        }
        // Always overwrite (even with null) so the hint reflects THIS
        // source's failure, never a stale one from an earlier attempt.
        fallbackHint = hint;
        continue; // unavailable / episode not found → try next source
      }

      final prov = _providerFromStored(source.debridService);
      final nativeCloud = source.isProviderNativeCloud;
      final t = nativeCloud ? null : _torrentFromSource(source);
      _Resolved? res;
      // Default reason if this attempt fails without a more specific one
      // (no magnet, empty play URL, not-cached, transient error) — Home's
      // generic wording. Overwritten below when we know more.
      fallbackHint =
          'Saved source is no longer available. Falling back to search.';
      try {
        final _Resolved? r;
        if (nativeCloud) {
          r = await _resolveProviderNativeBound(source, meta);
        } else {
          final magnet = await _magnetFor(t!);
          if (magnet == null) continue;
          if (cancel.cancelled) return true;
          r = await _add(prov, magnet, t);
        }
        if (r != null && r.playUrl != null && r.playUrl!.isNotEmpty) {
          if (season != null &&
              episode != null &&
              !_resolvedHasEpisode(r, season, episode)) {
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
            if (!nativeCloud &&
                PlaybackServiceDispatch.deletesRdOrphan(prov) &&
                (r.rdTorrentId?.isNotEmpty ?? false)) {
              try {
                final apiKey = (await StorageService.getApiKey()) ?? '';
                await DebridService.deleteTorrent(apiKey, r.rdTorrentId!);
              } catch (_) {}
            } else if (!nativeCloud &&
                PlaybackServiceDispatch.deletesPikPakOrphan(prov) &&
                (r.pikpakFileId?.isNotEmpty ?? false)) {
              try {
                await PikPakApiService.instance.batchDeleteFiles([
                  r.pikpakFileId!,
                ]);
              } catch (_) {}
            }
          } else {
            res = r;
          }
        }
      } on TorrentNotCachedException catch (e) {
        // Bound RD source is no longer cached → self-heal and try the next.
        try {
          await DebridService.deleteTorrent(e.apiKey, e.torrentId);
        } catch (_) {}
        await SeriesSourceService.removeSourceEntry(imdbId, source);
      } on AllDebridTorrentNotReadyException catch (e) {
        // Transient (still resolving) — keep the binding, just fail this attempt.
        try {
          await AllDebridService.deleteMagnet(e.apiKey, e.magnetId);
        } catch (_) {}
        fallbackHint =
            'Saved source is not ready on AllDebrid. Falling back to search.';
      } catch (_) {
        // TorBox/Premiumize uncached or transient — keep binding, try next.
      }
      if (cancel.cancelled) return true;
      if (res != null) {
        overlay.setStage(PlayLoadStage.starting);
        if (!context.mounted) {
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
          meta: meta,
          sources: nativeCloud ? null : [t!],
          sourceIndex: 0,
          // Bound play searched NOTHING — every applicable "Load more"
          // shows. Each factory self-gates on content type, so exactly one
          // (or neither, for non-tt ids) is non-null.
          seriesFetcher: nativeCloud
              ? null
              : (PlaybackSourceFetchers.seriesFetcherFor(
                      meta: meta,
                      provider: prov,
                    ) ??
                    PlaybackSourceFetchers.movieFetcherFor(
                      meta: meta,
                      provider: prov,
                    )),
          overlay: overlay,
          startupFailoverEnabled: true,
          onStartupSourcesExhausted: () => _recoverAfterBoundStartupFailure(
            context,
            imdbId,
            remainingSources,
            label: label,
            meta: meta,
            preferredProvider: preferredProvider,
          ),
        );
        return true;
      }
      if (!context.mounted) {
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
  }) async {
    if (!context.mounted) return;
    if (remainingSources.isNotEmpty) {
      final played = await _playViaBound(
        context,
        imdbId,
        remainingSources,
        label: label,
        meta: meta,
        preferredProvider: preferredProvider,
      );
      if (played || !context.mounted) return;
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
  }) async {
    if (imdbId.isEmpty) {
      _snack(context, 'No IMDb match — can\'t pin a source.');
      return false;
    }
    final provider = await _pickProvider(context);
    if (!context.mounted || provider == _cancelled) return false;
    if (provider == null) {
      _snack(context, 'No debrid provider configured. Add one in Settings.');
      return false;
    }
    // Capture the root navigator BEFORE showing the loader so we can always
    // dismiss it — even if the screen tears down during the await (otherwise the
    // barrier-less full-screen loader can get stuck covering the whole app).
    final rootNav = Navigator.of(context, rootNavigator: true);
    _showLoading(context, provider, torrent.name);
    _Resolved? res;
    String? failMessage;
    try {
      final magnet = await _magnetFor(torrent);
      if (magnet != null) {
        final r = await _add(provider, magnet, torrent);
        if (r.playUrl != null && r.playUrl!.isNotEmpty) res = r;
      }
    } on TorrentNotCachedException catch (e) {
      try {
        await DebridService.deleteTorrent(e.apiKey, e.torrentId);
      } catch (_) {}
    } on AllDebridTorrentNotReadyException catch (e) {
      try {
        await AllDebridService.deleteMagnet(e.apiKey, e.magnetId);
      } catch (_) {}
    } on PikPakStillProcessing {
      // PikPak queued a download that isn't instantly playable — can't pin.
      failMessage =
          'Added to PikPak — it\'s still downloading. Pin it again once ready.';
    } on PikPakFailed {
      failMessage = 'Download failed on PikPak.';
    } catch (_) {}
    // Pop the loader FIRST (using the captured navigator, no context), then
    // guard context use.
    if (rootNav.canPop()) rootNav.pop();
    if (!context.mounted) return false;
    if (res == null) {
      _snack(
        context,
        failMessage ??
            'That source isn\'t instantly playable on ${_label(provider)} — pick a cached one.',
      );
      return false;
    }
    final source = SeriesSource(
      torrentHash: torrent.infohash,
      torrentName: torrent.name,
      debridService: storedProviderKey(provider),
      debridTorrentId: '',
      boundAt: DateTime.now().millisecondsSinceEpoch,
    );
    if (isMovie) {
      await SeriesSourceService.setSources(imdbId, [source]);
    } else {
      await SeriesSourceService.addSource(imdbId, source);
    }
    if (context.mounted) _snack(context, 'Source pinned for instant playback.');
    return true;
  }

  /// Pin a playable Stremio addon stream without persisting its usually
  /// signed/temporary URL. Playback re-queries the same addon and stream
  /// profile for each movie play or requested series episode.
  static Future<bool> bindDirectSource(
    BuildContext context,
    Torrent torrent, {
    required String imdbId,
    required bool isMovie,
  }) async {
    if (imdbId.isEmpty) {
      _snack(context, 'No IMDb match — can\'t pin a source.');
      return false;
    }
    final source = _durableBindingForSource(
      torrent,
      SeriesSource.addonDirectService,
    );
    if (source == null || !source.isAddonDirect) {
      _snack(context, 'This direct stream cannot be refreshed by its addon.');
      return false;
    }
    if (isMovie) {
      await SeriesSourceService.setSources(imdbId, [source]);
    } else {
      await SeriesSourceService.addSource(imdbId, source);
    }
    if (context.mounted) {
      _snack(context, 'Direct source pinned for fresh-link playback.');
    }
    return true;
  }

  /// Pin an ON-DEVICE file (movie) or folder (series) as [imdbId]'s source via
  /// the shared local picker. Desktop-only — the picker shows its own
  /// "unavailable on mobile" message on Android/iOS (matching Home). Returns
  /// true if a local source was pinned.
  static Future<bool> bindLocalSource(
    BuildContext context, {
    required String imdbId,
    required bool isMovie,
    required String title,
    String? year,
  }) async {
    if (imdbId.isEmpty) {
      _snack(context, 'No IMDb match — can\'t pin a source.');
      return false;
    }
    final SeriesSource? source;
    if (isMovie) {
      source = await LocalBoundSourceService.pickMovieSource(
        context,
        title: title,
        year: year,
      );
    } else {
      source = await LocalBoundSourceService.pickSeriesSource(
        context,
        title: title,
      );
    }
    if (source == null || !context.mounted) return false;
    if (isMovie) {
      await SeriesSourceService.setSources(imdbId, [source]);
    } else {
      await SeriesSourceService.addSource(imdbId, source);
    }
    if (context.mounted) _snack(context, 'Local source pinned.');
    return true;
  }

  /// Whether on-device local binding is available on this platform (false on
  /// Android/iOS). Lets the UI hide/adjust the local-pin affordance.
  static bool get localBindingAvailable =>
      !LocalBoundSourceService.isLocalBindingDisabled;

  // ── Per-provider add + resolve ─────────────────────────────────────────────

  static Future<_Resolved> _add(
    String provider,
    String magnet,
    Torrent torrent,
  ) => CloudProviderRegistry.instance.addMagnet(provider, magnet, torrent);

  // ── Post-action branch handlers ────────────────────────────────────────────

  static Future<void> _play(
    BuildContext context,
    _Resolved r,
    Torrent torrent, {
    required String provider,
    PlaybackMeta? meta,
    List<Torrent>? sources,
    int sourceIndex = 0,
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
        if (!context.mounted) return;
        unawaited(
          _advanceToNextEpisode(
            context,
            imdbId: imdbId,
            meta: nextMeta,
            provider: provider,
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
  }) async {
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
      );
      return;
    }
    final bound = await SeriesSourceService.getSources(imdbId);
    if (!context.mounted) return;
    if (bound.isNotEmpty && meta.season != null && meta.episode != null) {
      final played = await _playViaBound(
        context,
        imdbId,
        bound,
        label: label,
        meta: meta,
      );
      if (played) return;
      if (!context.mounted) return;
    }
    final rules = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: false);
    if (!context.mounted) return;
    await _playAddonStream(
      context,
      imdbId,
      isMovie: false,
      season: meta.season,
      episode: meta.episode,
      meta: meta,
      label: label,
      rules: rules,
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
    Future<List<PlaylistEntry>?> Function(Torrent)? resolveSourceToPlaylist,
    bool startupFailoverEnabled = false,
    String? startupResolverProvider,
    Future<void> Function(Torrent)? onStremioSourceCommitted,
    Future<void> Function()? onStartupSourcesExhausted,
    SeriesSourceFetcher? seriesSourceFetcher,
    PlaybackMeta? meta,
    String? rdTorrentId,
    int? torboxTorrentId,
    PlaylistViewMode? viewMode,
  }) => VideoPlayerLaunchArgs(
    videoUrl: videoUrl,
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
    seriesSourceFetcher: seriesSourceFetcher,
    contentImdbId: meta?.imdbId,
    contentType: meta?.contentType,
    contentSeason: meta?.season,
    contentEpisode: meta?.episode,
    contentTitle: meta?.title,
    posterUrl: meta?.posterUrl,
    contentYear: meta?.year,
    addonId: meta?.addonId,
    traktScrobble: meta?.traktScrobble ?? false,
    traktProgressPercent: meta?.traktProgressPercent,
    simklScrobble: meta?.simklScrobble ?? false,
    simklProgressPercent: meta?.simklProgressPercent,
    mdblistScrobble: meta?.mdblistScrobble ?? false,
    mdblistProgressPercent: meta?.mdblistProgressPercent,
    resumePolicy: meta?.resumePolicy ?? PlaybackResumePolicy.sourceSpecific,
    // Debrid torrent ids let the player back-fill poster/IMDb onto a saved
    // Playlist-library entry and power the in-player "Fix Metadata" action
    // (matching Home). PikPak is intentionally omitted: the launcher wants a
    // collection/folder id, but _Resolved only carries a per-file id.
    rdTorrentId: rdTorrentId,
    torboxTorrentId: torboxTorrentId?.toString(),
  );

  @visibleForTesting
  static VideoPlayerLaunchArgs playerArgsForTesting(PlaybackMeta? meta) =>
      _playerArgs(videoUrl: 'video', title: 'Title', meta: meta);

  /// In-player Sources-switcher resolver for launches that didn't go through a
  /// debrid provider (direct addon streams). Direct streams resolve without
  /// one; a torrent switch silently uses the default/first-configured provider
  /// (matching Home's _createSourcePlaylistResolver) and fails gracefully
  /// (null) when none is configured.
  static Future<List<PlaylistEntry>?> Function(Torrent)
  _lazyProviderResolver() {
    return (Torrent t) async {
      if (t.streamType == StreamType.directUrl &&
          (t.directUrl?.isNotEmpty ?? false)) {
        return [PlaylistEntry(url: t.directUrl!, title: t.displayTitle)];
      }
      final provider =
          await PlaybackProviderResolution.defaultConfiguredProvider();
      if (provider == null) return null;
      return _resolverFor(provider)(t);
    };
  }

  /// Old-screen parity: playing a catalog MOVIE remembers the just-played
  /// validated source as that title's single bound source (override), so the
  /// catalog flips "Select Source" → "Edit Source" and the next play reuses
  /// it.
  /// Series use the accumulating path below; keyword play (meta == null) and
  /// non-IMDb / on-device plays don't bind either. Best-effort — a storage
  /// hiccup must never break playback.
  static Future<void> _autoBindMovieOnPlay(
    PlaybackMeta? meta,
    Torrent? winner,
    String provider,
  ) async {
    if (meta == null ||
        meta.contentType != 'movie' ||
        meta.imdbId == null ||
        meta.imdbId!.isEmpty ||
        winner == null) {
      return;
    }
    final source = _durableBindingForSource(winner, provider);
    if (source == null) return;
    try {
      await SeriesSourceService.setSources(meta.imdbId!, [source]);
    } catch (_) {}
  }

  /// Series counterpart of [_autoBindMovieOnPlay] (on by default via the
  /// series auto-pin setting): pin whatever source a series play resolved to
  /// — a pack from the pack-first search or a single episode from the fallback
  /// — so subsequent plays go straight through the bound path. A replayed
  /// binding is refreshed and promoted to primary; a new single-episode
  /// binding is capped so a pack-less show binged over time can't grow the
  /// list without bound (older singles are evicted; packs are never touched).
  /// Refreshable addon-direct sources participate without persisting their
  /// signed/temporary URL, and count toward that cap like any other single —
  /// exempting them left the list unbounded. A manually pinned SINGLE is
  /// therefore evictable once 20 accumulate for one series; there is no stored
  /// manual/auto flag to tell them apart, and an unbounded list is the worse
  /// failure. Local sources stay opt-in.
  ///
  /// Gated on [QuickPlayPolicyPrefs.getSeriesAutoPinOnPlay] — which is NOT the
  /// "Prefer season packs" toggle. The two shared a preference key until it was
  /// split; turning packs off used to disable pinning here, which left Smart
  /// mode permanently unable to find a pin.
  static const int _maxAutoBoundSingles = 20;

  static Future<void> _autoBindSeriesOnPlay(
    PlaybackMeta? meta,
    Torrent? winner,
    String provider,
  ) async {
    // Any non-movie episode play (contentType 'series' or a custom series-like
    // type such as anime) — movies are handled by _autoBindMovieOnPlay.
    // Scoped to episode plays (season+episode set) to match the pack-first
    // gate and skip whole-series/no-episode plays.
    if (meta == null ||
        meta.contentType == 'movie' ||
        meta.imdbId == null ||
        meta.imdbId!.isEmpty ||
        meta.season == null ||
        meta.episode == null ||
        winner == null ||
        // Consistent with the pack-first block: the whole auto-pin feature is
        // off for PikPak (its bindings re-queue real downloads on each replay),
        // so a stale-true pref after switching default to PikPak stays inert.
        (winner.streamType == StreamType.torrent &&
            PlaybackServiceDispatch.skipSeriesTorrentPin(provider))) {
      return;
    }
    final source = _durableBindingForSource(winner, provider);
    if (source == null) return;
    try {
      if (!await QuickPlayPolicyPrefs.getSeriesAutoPinOnPlay()) return;
      final imdbId = meta.imdbId!;
      final list = List<SeriesSource>.from(
        await SeriesSourceService.getSources(imdbId),
      );
      final existingIdx = list.indexWhere(
        (s) => s.bindingKey == source.bindingKey,
      );
      if (existingIdx >= 0) {
        // The source that actually rendered becomes primary, while every
        // other series fallback remains available.
        list.removeAt(existingIdx);
      } else {
        // A NEW single-episode binding: bound how many auto-accumulate so a
        // pack-less show doesn't grow the list forever. Packs and anything else
        // that isn't a single episode are never evicted.
        //
        // Addon-direct singles count here too. Exempting them left the list
        // unbounded, and an unstable identity (see SeriesSource.bindingKey)
        // appended a fresh one on every play. The identity is fixed now; this
        // cap is the backstop for whatever destabilises it next. The cost is
        // that a manually pinned single is evictable once 20 accumulate —
        // there is no stored manual/auto flag to separate them.
        if (_singleEpisodeOf(source.torrentName) != null) {
          final singles =
              list
                  .where((s) => _singleEpisodeOf(s.torrentName) != null)
                  .toList()
                ..sort((a, b) => a.boundAt.compareTo(b.boundAt));
          final overflow = singles.length + 1 - _maxAutoBoundSingles;
          if (overflow > 0) {
            final drop = singles
                .take(overflow)
                .map((s) => s.bindingKey)
                .toSet();
            list.removeWhere((s) => drop.contains(s.bindingKey));
          }
        }
      }
      list.insert(0, source);
      await SeriesSourceService.setSources(imdbId, list);
    } catch (_) {}
  }

  /// Converts an eligible playback source into its durable binding. Automatic
  /// callers invoke this only after decoder validation. Direct streams keep
  /// only opaque addon provenance so the next play re-queries a fresh URL;
  /// arbitrary/external links and local rows cannot be auto-bound.
  static SeriesSource? _durableBindingForSource(
    Torrent source,
    String provider,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (source.streamType == StreamType.directUrl) {
      final addonId = source.stremioAddonId;
      final addonKey = source.stremioAddonKey;
      final streamKey = source.stremioStreamKey;
      if (addonId == null ||
          addonId.isEmpty ||
          addonKey == null ||
          addonKey.isEmpty ||
          streamKey == null ||
          streamKey.isEmpty) {
        return null;
      }
      return SeriesSource(
        torrentHash: '',
        torrentName: source.name,
        debridService: SeriesSource.addonDirectService,
        debridTorrentId: '',
        boundAt: now,
        addonId: addonId,
        addonKey: addonKey,
        streamKey: streamKey,
        streamIndex: source.stremioStreamIndex ?? 0,
      );
    }
    if (source.streamType != StreamType.torrent ||
        source.infohash.isEmpty ||
        provider == SeriesSource.localService ||
        provider == SeriesSource.addonDirectService) {
      return null;
    }
    return SeriesSource(
      torrentHash: source.infohash,
      torrentName: source.name,
      debridService: storedProviderKey(provider),
      debridTorrentId: '',
      boundAt: now,
    );
  }

  /// Launch the player. Passes the full source list + a resolver (so the player
  /// shows the in-player "Sources" switcher) and content metadata (so Continue
  /// Watching, subtitles and the Episodes button work) — matching Home.
  static Future<void> _launch(
    BuildContext context,
    _Resolved r,
    String title, {
    required String provider,
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
  }) async {
    // Once push() takes the handoff callback the LAUNCHER owns the dismissal
    // (player-visible time, or its own always-fires safety net); the finally
    // here only covers exits before that point. dismiss() is idempotent.
    var loaderHandedToLauncher = false;
    try {
      // Secondary metadata line (file size / source / file count), matching Home.
      final winner =
          (sources != null && sourceIndex >= 0 && sourceIndex < sources.length)
          ? sources[sourceIndex]
          : null;
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
        if (!context.mounted) return;
        await _launchWithDeoVR(context, videoUrl: r.playUrl!, filename: title);
        return;
      }
      // Args built BEFORE the flag flips: a throw while constructing them
      // must still hit the finally's dismiss, since push() never ran.
      final args = _playerArgs(
        videoUrl: r.playUrl!,
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
            ? (provider == SeriesSource.localService ||
                      provider == SeriesSource.addonDirectService
                  ? _lazyProviderResolver()
                  : _resolverFor(provider))
            : null,
        startupFailoverEnabled: startupFailoverEnabled,
        startupResolverProvider:
            provider == SeriesSource.localService ||
                provider == SeriesSource.addonDirectService
            ? null
            : provider,
        onStremioSourceCommitted:
            provider == SeriesSource.localService ||
                provider == SeriesSource.addonDirectService
            ? _lazySourceCommitter(meta)
            : _validatedLaunchCommitter(provider, meta),
        onStartupSourcesExhausted: onStartupSourcesExhausted,
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
        provider:
            provider == SeriesSource.localService ||
                provider == SeriesSource.addonDirectService
            ? null
            : provider,
      );
      loaderHandedToLauncher = overlay != null;
      await VideoPlayerLauncher.push(
        context,
        args,
        onPlayerHandoff: overlay?.dismiss,
        onQuickPlayNextEpisode: nextEpisodeHandler,
      );
    } finally {
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
  static Future<List<PlaylistEntry>?> Function(Torrent) _resolverFor(
    String provider,
  ) {
    return (Torrent t) async {
      if (t.streamType == StreamType.directUrl &&
          (t.directUrl?.isNotEmpty ?? false)) {
        return [PlaylistEntry(url: t.directUrl!, title: t.displayTitle)];
      }
      final magnet = await _magnetFor(t);
      if (magnet == null) return null;
      try {
        final r = await _add(provider, magnet, t);
        if (r.playlist != null && r.playlist!.isNotEmpty) return r.playlist;
        if (r.playUrl != null && r.playUrl!.isNotEmpty) {
          return [PlaylistEntry(url: r.playUrl!, title: t.displayTitle)];
        }
      } catch (_) {}
      return null;
    };
  }

  /// The first validated candidate owns the normal play-time auto-binding;
  /// later commits are explicit in-player switches. Commits are serialized so
  /// rapid successful switches cannot let an older SharedPreferences write
  /// land after a newer one. Movies replace their sole binding; series retain
  /// prior bindings and promote the newly validated source.
  static Future<void> Function(Torrent) _validatedLaunchCommitter(
    String provider,
    PlaybackMeta? meta,
  ) {
    var initialCommitPending = true;
    var tail = Future<void>.value();
    return (Torrent t) {
      final isInitial = initialCommitPending;
      if (initialCommitPending) {
        initialCommitPending = false;
      }
      final commit = tail.then((_) async {
        var bindingProvider = provider;
        if (t.streamType == StreamType.torrent &&
            bindingProvider == SeriesSource.addonDirectService) {
          bindingProvider =
              await PlaybackProviderResolution.defaultConfiguredProvider() ??
              bindingProvider;
        }
        if (isInitial) {
          await _autoBindMovieOnPlay(meta, t, bindingProvider);
          await _autoBindSeriesOnPlay(meta, t, bindingProvider);
          return;
        }
        await _rebindOnSourceSwitch(meta, t, bindingProvider);
      });
      // Keep the chain usable even though persistence is deliberately
      // best-effort. Return the original task so the bridge still observes a
      // failure if a future implementation stops swallowing storage errors.
      tail = commit.catchError((_) {});
      return commit;
    };
  }

  /// Public only for persistence regression tests; production players receive
  /// the same callback through [_validatedLaunchCommitter].
  @visibleForTesting
  static Future<void> Function(Torrent) validatedSourceCommitterForTesting(
    String provider,
    PlaybackMeta? meta,
  ) => _validatedLaunchCommitter(provider, meta);

  /// Commit hook for launches whose resolver chooses a provider lazily.
  static Future<void> Function(Torrent) _lazySourceCommitter(
    PlaybackMeta? meta,
  ) {
    var tail = Future<void>.value();
    return (Torrent t) {
      final commit = tail.then((_) async {
        if (t.streamType == StreamType.directUrl) {
          await _rebindOnSourceSwitch(meta, t, SeriesSource.addonDirectService);
          return;
        }
        final provider =
            await PlaybackProviderResolution.defaultConfiguredProvider();
        if (provider == null) return;
        await _rebindOnSourceSwitch(meta, t, provider);
      });
      tail = commit.catchError((_) {});
      return commit;
    };
  }

  /// Keep a title's pinned source in sync when the user switches sources in
  /// the player. A validated switch can update or create the binding; local and
  /// non-refreshable sources are skipped.
  ///
  /// A movie has a single bound source, so it's a straight replace (matching
  /// [_autoBindMovieOnPlay]). A series keeps ALL other fallbacks and promotes
  /// the chosen source to primary; switching never replaces a series pin.
  /// PikPak torrents are excluded for series
  /// (matching the series auto-pin feature) but allowed for movies (matching
  /// [_autoBindMovieOnPlay]).
  static Future<void> _rebindOnSourceSwitch(
    PlaybackMeta? meta,
    Torrent switched,
    String provider,
  ) async {
    if (meta == null ||
        meta.imdbId == null ||
        meta.imdbId!.isEmpty ||
        switched.streamType == StreamType.externalUrl) {
      return;
    }
    final isMovie = meta.contentType == 'movie';
    // A series needs a concrete episode, and its auto-pin feature is off for
    // PikPak; movies have neither constraint.
    if (!isMovie &&
        (meta.season == null ||
            meta.episode == null ||
            (switched.streamType == StreamType.torrent &&
                PlaybackServiceDispatch.skipSeriesTorrentPin(provider)))) {
      return;
    }
    final source = _durableBindingForSource(switched, provider);
    if (source == null) return;
    try {
      final imdbId = meta.imdbId!;
      final existing = await SeriesSourceService.getSources(imdbId);
      if (isMovie) {
        // Single bound source — replace it with the chosen one.
        await SeriesSourceService.setSources(imdbId, [source]);
        return;
      }
      // A switch after an unpersistable initial row can be the first bind. The
      // existing series auto-pin preference still owns that opt-in boundary;
      // once a list exists, a successful switch keeps it in sync regardless.
      if (existing.isEmpty && !await QuickPlayPolicyPrefs.getSeriesAutoPinOnPlay()) {
        return;
      }
      // Series: promote the winner but retain the previous primary and every
      // other fallback. Re-selecting an existing entry just moves/refreshes it.
      final list = List<SeriesSource>.from(existing)
        ..removeWhere((s) => s.bindingKey == source.bindingKey);
      list.insert(0, source);
      await SeriesSourceService.setSources(imdbId, list);
    } catch (_) {}
  }

  /// Download a direct/external addon stream to device (parity with the old
  /// screen's direct-stream "Download to device" action). Follows redirects
  /// first — MediaFusion-style playback URLs 30x-hop to the real file — then
  /// queues the resolved URL.
  static Future<void> downloadDirectStream(
    BuildContext context,
    Torrent torrent,
  ) async {
    final raw = torrent.directUrl ?? '';
    if (raw.isEmpty) {
      _snack(context, 'No stream URL available.');
      return;
    }
    _snack(context, 'Resolving download URL…');
    final resolved = await _resolveDownloadUrl(raw);
    try {
      await DownloadService.instance.enqueueDownload(
        url: resolved,
        fileName: torrent.displayTitle,
        torrentName: torrent.displayTitle,
      );
      if (context.mounted) _snack(context, 'Download queued.');
    } catch (_) {
      if (context.mounted) _snack(context, 'Failed to queue download.');
    }
  }

  /// Follow up to 10 redirects (HEAD, no auto-follow) to resolve a stream URL to
  /// its final downloadable location, handling relative Location headers. Ported
  /// from the old screen's `_resolveDownloadUrl`.
  static Future<String> _resolveDownloadUrl(String url) async {
    var currentUrl = url;
    var redirectCount = 0;
    while (redirectCount < 10) {
      try {
        final uri = Uri.parse(currentUrl);
        final client = http.Client();
        try {
          final request = http.Request('HEAD', uri);
          request.followRedirects = false;
          request.headers['User-Agent'] =
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
          final response = await client
              .send(request)
              .timeout(const Duration(seconds: 10));
          if (response.statusCode == 301 ||
              response.statusCode == 302 ||
              response.statusCode == 303 ||
              response.statusCode == 307 ||
              response.statusCode == 308) {
            final location = response.headers['location'];
            if (location != null && location.isNotEmpty) {
              currentUrl = uri.resolve(location).toString();
              redirectCount++;
              continue;
            }
          }
          return currentUrl; // no redirect → final URL
        } finally {
          client.close();
        }
      } catch (_) {
        break;
      }
    }
    return currentUrl; // best effort (possibly partially resolved)
  }

  /// Resolve a playlist entry to a concrete download URL, unlocking a lazy
  /// debrid entry on demand: RD `restrictedLink` → unrestrict, TorBox
  /// torrent+file id → download link, AllDebrid locked link → unlock. Premiumize
  /// entries already carry a URL. Returns null if it can't be resolved.
  static Future<String?> _resolveEntryUrl(PlaylistEntry e) =>
      CloudProviderRegistry.instance.resolveEntryUrl(e);

  /// Multi-select download picker (parity with the old per-file download
  /// dialog): lists the pack's files with sizes, defaults all selected, shows a
  /// running total, and returns the chosen entries — or null if cancelled.
  static Future<List<PlaylistEntry>?> _showDownloadPicker(
    BuildContext context,
    List<PlaylistEntry> entries,
  ) {
    return showDialog<List<PlaylistEntry>>(
      context: context,
      builder: (dialogCtx) {
        final scheme = Theme.of(dialogCtx).colorScheme;
        final selected = {...entries}; // default: all selected
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final totalBytes = selected.fold<int>(
              0,
              (sum, e) => sum + (e.sizeBytes ?? 0),
            );
            final allOn = selected.length == entries.length;
            return AlertDialog(
              title: const Text('Download files'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => setLocal(() {
                          if (allOn) {
                            selected.clear();
                          } else {
                            selected
                              ..clear()
                              ..addAll(entries);
                          }
                        }),
                        child: Text(allOn ? 'None' : 'All'),
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final e in entries)
                            CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: selected.contains(e),
                              title: Text(
                                e.title,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurface,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              secondary: Text(
                                (e.sizeBytes ?? 0) > 0
                                    ? Formatters.formatFileSize(e.sizeBytes!)
                                    : '',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              onChanged: (_) => setLocal(() {
                                if (selected.contains(e)) {
                                  selected.remove(e);
                                } else {
                                  selected.add(e);
                                }
                              }),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.of(
                          dialogCtx,
                        ).pop(entries.where(selected.contains).toList()),
                  child: Text(
                    totalBytes > 0
                        ? 'Download · ${Formatters.formatFileSize(totalBytes)}'
                        : 'Download',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static Future<void> _download(
    BuildContext context,
    _Resolved r,
    Torrent torrent,
    String provider,
  ) async {
    // Multi-file pack: let the user choose which files (parity with the old
    // per-file download dialog), then queue each — unlocking lazy debrid entries
    // on demand (RD/TorBox/AllDebrid resolve only the start file up front;
    // Premiumize resolves all).
    if (r.playlist != null && r.playlist!.length > 1) {
      final chosen = await _showDownloadPicker(context, r.playlist!);
      if (chosen == null || chosen.isEmpty) return; // cancelled
      var n = 0;
      for (final e in chosen) {
        final url = await _resolveEntryUrl(e);
        if (url == null || url.isEmpty) continue;
        if (await DownloadService.instance.enqueueCloudFile(
          provider: provider,
          url: url,
          fileName: e.title,
          torrentName: torrent.displayTitle,
        )) {
          n++;
        }
      }
      if (context.mounted) {
        _snack(
          context,
          n > 0
              ? 'Queued $n file(s) for download.'
              : 'Could not queue downloads.',
        );
      }
      return;
    }
    if (r.playlist != null && r.playlist!.isNotEmpty) {
      // Single-entry playlist: queue it directly (no picker for one file).
      final url = await _resolveEntryUrl(r.playlist!.first);
      var queued = false;
      if (url != null && url.isNotEmpty) {
        queued = await DownloadService.instance.enqueueCloudFile(
          provider: provider,
          url: url,
          fileName: r.playlist!.first.title,
          torrentName: torrent.displayTitle,
        );
      }
      if (context.mounted) {
        _snack(
          context,
          queued ? 'Download queued.' : 'Could not queue download.',
        );
      }
      return;
    }
    final url = r.downloadUrls.isNotEmpty ? r.downloadUrls.first : null;
    if (url == null) {
      _snack(context, 'Nothing to download for this source.');
      return;
    }
    await DownloadService.instance.enqueueCloudFile(
      provider: provider,
      url: url,
      fileName: r.fileName ?? torrent.displayTitle,
      torrentName: torrent.displayTitle,
    );
    if (context.mounted) _snack(context, 'Download queued.');
  }

  static Future<void> _addToPlaylist(
    BuildContext context,
    _Resolved r,
    Torrent torrent,
    String provider, {
    PlaybackMeta? meta,
  }) async {
    final isPack = r.hasPlaylist;
    final rawTitle = (!isPack && r.fileName != null)
        ? r.fileName!
        : torrent.displayTitle;
    // No 'url' is stored — the playlist player re-resolves from provider-native
    // ids after the debrid direct link expires.
    final item = CloudPlaylistPayload.build(
      provider: provider,
      result: r,
      torrentHash: torrent.infohash,
      title: FileUtils.cleanPlaylistTitle(rawTitle),
      sizeBytes: torrent.sizeBytes,
      imdbId: meta?.imdbId,
      contentType: meta?.contentType,
      posterUrl: meta?.posterUrl,
    );
    final ok = await PlaybackProgressStore.addPlaylistItemRaw(item);
    if (context.mounted) {
      _snack(context, ok ? 'Added to playlist.' : 'Already in playlist.');
    }
  }

  /// The app's real post-add chooser (glass card + styled tiles), with the full
  /// option set — Play / Download / Add to playlist / Add to channel / Open in
  /// provider tab — matching Home's per-provider sheets.
  static Future<void> _showChooser(
    BuildContext context,
    _Resolved r,
    Torrent torrent,
    String provider, {
    String? magnet,
    PlaybackMeta? meta,
    List<Torrent>? sources,
    int sourceIndex = 0,
    String searchKeyword = '',
  }) async {
    final hasVideo = r.playUrl != null && r.playUrl!.isNotEmpty;
    final name = torrent.displayTitle;
    await showDebridActionSheet(
      context,
      providerLabel: _label(provider),
      torrentName: name,
      gradient: _providerGradient(provider),
      provider: provider,
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
            onTap: () => unawaited(_download(context, r, torrent, provider)),
          ),
        DebridActionItem(
          icon: Icons.playlist_add_rounded,
          color: const Color(0xFF8B5CF6),
          title: 'Add to playlist',
          subtitle: 'Save it to your playlist for later.',
          pillLabel: 'Playlist',
          enabled: hasVideo,
          onTap: () => unawaited(
            _addToPlaylist(context, r, torrent, provider, meta: meta),
          ),
        ),
        DebridActionItem(
          icon: Icons.connected_tv,
          color: const Color(0xFF14B8A6),
          title: 'Add to channel',
          subtitle: 'Cache this torrent in a Debrify TV channel.',
          onTap: () => unawaited(
            DebrifyTvChannelAddService.addTorrentsToChannel(
              context,
              torrents: [torrent],
              searchKeyword: searchKeyword,
            ),
          ),
        ),
        // TorBox power actions: download the whole-torrent ZIP to device, or
        // copy its permalink (parity with the old screen's TorBox download menu).
        if (PlaybackServiceDispatch.showTorboxPowerActions(provider) && r.torboxTorrentId != null) ...[
          DebridActionItem(
            icon: Icons.folder_zip_rounded,
            color: const Color(0xFFA78BFA),
            title: 'Download as ZIP',
            subtitle: 'Download all files as a ZIP to this device.',
            onTap: () => unawaited(
              _downloadTorboxZip(context, r.torboxTorrentId!, name),
            ),
          ),
          DebridActionItem(
            icon: Icons.link_rounded,
            color: const Color(0xFFEC4899),
            title: 'Copy Download Link (Zip)',
            subtitle: 'Copy ZIP download link to clipboard.',
            onTap: () =>
                unawaited(_copyTorboxZipLink(context, r.torboxTorrentId!)),
          ),
        ],
        // Premiumize power actions (need the magnet — cloud transfer + ZIP).
        if (PlaybackServiceDispatch.showPremiumizePowerActions(provider) && magnet != null) ...[
          DebridActionItem(
            icon: Icons.cloud_upload_rounded,
            color: const Color(0xFFF59E0B),
            title: 'Transfer to Premiumize',
            subtitle: 'Add this torrent to your Premiumize cloud.',
            onTap: () => unawaited(_premiumizeTransfer(context, magnet)),
          ),
          DebridActionItem(
            icon: Icons.folder_zip_rounded,
            color: const Color(0xFFA78BFA),
            title: 'Download as ZIP',
            subtitle: 'Transfer to cloud and download all files as a ZIP.',
            onTap: () => unawaited(
              _premiumizeZip(context, magnet, name, copyOnly: false),
            ),
          ),
          DebridActionItem(
            icon: Icons.link_rounded,
            color: const Color(0xFFEC4899),
            title: 'Copy ZIP Link',
            subtitle: 'Copy ZIP download link to clipboard.',
            onTap: () => unawaited(
              _premiumizeZip(context, magnet, name, copyOnly: true),
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
            onTap: () => r.openInTab!.call(),
          ),
      ],
    );
  }

  // ── Provider-specific power actions (TorBox / Premiumize) ───────────────────

  static Future<void> _copyTorboxZipLink(
    BuildContext context,
    int torrentId,
  ) async {
    final apiKey = (await StorageService.getTorboxApiKey()) ?? '';
    if (apiKey.isEmpty) return;
    final zipLink = await CloudProviderRegistry.instance.zipPermalink(torrentId);
    await Clipboard.setData(ClipboardData(text: zipLink));
    if (context.mounted) {
      _snack(context, 'ZIP download link copied to clipboard!');
    }
  }

  /// Queue the whole-torrent ZIP for download to this device (parity with the
  /// old TorBox "Download as ZIP to device" option). The `torboxZip` meta lets
  /// the download service key/retry it as a ZIP job.
  static Future<void> _downloadTorboxZip(
    BuildContext context,
    int torrentId,
    String torrentName,
  ) async {
    final apiKey = (await StorageService.getTorboxApiKey()) ?? '';
    if (apiKey.isEmpty) return;
    final zipLink = await CloudProviderRegistry.instance.zipPermalink(torrentId);
    try {
      await DownloadService.instance.enqueueDownload(
        credentialKey: DownloadService.credentialKeyForCloudProvider(
          CloudProviderId.torbox.playbackId,
        ),
        url: zipLink,
        fileName: '$torrentName.zip',
        torrentName: torrentName,
        meta: jsonEncode({
          'torboxDownload': true,
          'torboxZip': true,
          'torboxTorrentId': torrentId,
        }),
      );
      if (context.mounted) _snack(context, 'ZIP download queued.');
    } catch (_) {
      if (context.mounted) _snack(context, 'Failed to queue ZIP download.');
    }
  }

  static Future<void> _premiumizeTransfer(
    BuildContext context,
    String magnet,
  ) async {
    final apiKey = (await StorageService.getPremiumizeApiKey()) ?? '';
    if (apiKey.isEmpty) return;
    try {
      await CloudProviderRegistry.instance.createCloudTransfer(magnet);
      if (context.mounted) {
        _snack(
          context,
          'Added to Premiumize. It will be available once the download finishes.',
        );
      }
    } catch (_) {
      if (context.mounted) _snack(context, 'Failed to transfer to Premiumize.');
    }
  }

  /// Generate the Premiumize ZIP (cloud transfer + zip), then either queue the
  /// download or copy the link — matching Home's "Download as ZIP" / "Copy ZIP
  /// Link" tiles. Shows the Premiumize loading overlay during the (slow) build.
  static Future<void> _premiumizeZip(
    BuildContext context,
    String magnet,
    String torrentName, {
    required bool copyOnly,
  }) async {
    final apiKey = (await StorageService.getPremiumizeApiKey()) ?? '';
    if (apiKey.isEmpty) return;
    if (!context.mounted) return;
    final rootNav = Navigator.of(context, rootNavigator: true);
    DebridLoadingOverlay.showForPlaybackId(
      context,
      CloudProviderId.premiumize.playbackId,
      torrentName,
    );
    // Only the (slow) ZIP generation is covered by the overlay. Popping happens
    // exactly once — the post-success clipboard/download step runs in its own
    // guard so a failure there can NEVER pop a second (underlying) route.
    final String zipUrl;
    try {
      zipUrl = await CloudProviderRegistry.instance.createTransferZip(magnet);
    } catch (_) {
      if (rootNav.canPop()) rootNav.pop();
      if (context.mounted) {
        _snack(
          context,
          copyOnly ? 'Failed to generate ZIP link.' : 'Failed to generate ZIP.',
        );
      }
      return;
    }
    if (rootNav.canPop()) rootNav.pop(); // dismiss the overlay exactly once
    try {
      if (copyOnly) {
        await Clipboard.setData(ClipboardData(text: zipUrl));
        if (context.mounted) {
          _snack(context, 'ZIP download link copied to clipboard!');
        }
      } else {
        await DownloadService.instance.enqueueDownload(
          credentialKey: DownloadService.credentialKeyForCloudProvider(
            CloudProviderId.premiumize.playbackId,
          ),
          url: zipUrl,
          fileName: '$torrentName.zip',
          torrentName: torrentName,
        );
        if (context.mounted) {
          _snack(context, 'ZIP download queued successfully.');
        }
      }
    } catch (_) {
      if (context.mounted) {
        _snack(
          context,
          copyOnly ? 'Failed to generate ZIP link.' : 'Failed to generate ZIP.',
        );
      }
    }
  }

  static List<Color> _providerGradient(String provider) =>
      CloudProviderPresentation.gradient(provider);

  // ── Not-cached handling (mirrors Home UX: warn, then keep-downloading) ──────

  static Future<void> _handleNotCached(
    BuildContext context,
    Object marker,
    String provider,
    String magnet,
  ) async {
    final keep = await showNotCachedDialog(context, _label(provider));
    if (!context.mounted) return;
    if (!keep) {
      if (marker is TorrentNotCachedException) {
        try {
          await DebridService.deleteTorrent(marker.apiKey, marker.torrentId);
        } catch (_) {}
      } else if (marker is AllDebridTorrentNotReadyException) {
        try {
          await AllDebridService.deleteMagnet(marker.apiKey, marker.magnetId);
        } catch (_) {}
      }
      return;
    }
    // "Add anyway": queue the download on the provider.
    try {
      await CloudProviderRegistry.instance.queueUncachedMagnet(
        provider,
        magnet,
      );
    } catch (_) {}
    // RD/AllDebrid already added the torrent while resolving; nothing more.
    if (context.mounted) {
      _snack(
        context,
        'Added — it will download on ${_label(provider)}. Play it once ready.',
      );
    }
  }

  // ── Provider resolution ────────────────────────────────────────────────────

  /// Resolves which provider to use. Honours the default; when none is set and
  /// more than one is configured, asks the user (mirrors Home's behaviour).
  static Future<String?> _pickProvider(BuildContext context) async {
    final (configured, def) =
        await PlaybackProviderResolution.configuredProviders();
    if (configured.isEmpty) return null;
    if (def != null) return def;
    if (configured.length == 1) return configured.first;
    if (!context.mounted) return _cancelled;
    final result = await showProviderPickerDialog(context, [
      for (final p in configured)
        ProviderPickerOption(
          id: p,
          label: _label(p),
          gradient: _providerGradient(p),
        ),
    ]);
    if (result == null) return _cancelled; // dismissed
    // "Remember my choice" persists the default so we never ask again.
    if (result.remember) {
      await ProviderCredentialPrefs.setDefaultTorrentProvider(result.provider);
    }
    return result.provider;
  }

  static Future<String> _postAction(String provider) async {
    final id = CloudProviderId.tryParse(provider);
    if (id == null) return ProviderCredentialPrefs.getPostTorrentAction();
    return CloudCredentials.postTorrentAction(id);
  }

  static Future<List<Torrent>> _cacheFirst(
    String provider,
    List<Torrent> candidates,
  ) => PlaybackCacheFirst.reorder(provider, candidates);

  static String _fileName(String path) => CloudPlaybackHelpers.fileName(path);

  /// True when a resolved playlist's file names look like a TV series (multiple
  /// files parseable as season/episode), so it should play in series view mode.
  static bool _isSeriesPlaylist(List<PlaylistEntry> entries) {
    if (entries.length <= 1) return false;
    final names = [for (final e in entries) _fileName(e.title)];
    return SeriesParser.isSeriesPlaylist(names);
  }

  static (List<T>, int) _orderBySeries<T>(
    List<T> items,
    String Function(T) nameOf,
  ) => CloudPlaybackHelpers.orderBySeries(items, nameOf);

  // ── Acquisition URL ────────────────────────────────────────────────────────

  /// Prefer a real magnet; else synthesize from the infohash (works across
  /// every provider); else convert a .torrent URL to a real magnet
  /// (magnet-only APIs — PikPak/TorBox/Premiumize/AllDebrid — can't accept a
  /// protected .torrent URL, matching Home's `_pikPakMagnetForTorrent`).
  static Future<String?> _magnetFor(Torrent t) async {
    final magnet = t.magnetUrl;
    if (magnet != null && magnet.startsWith('magnet:')) return magnet;
    if (t.hasRealInfoHash && t.infohash.isNotEmpty) {
      return 'magnet:?xt=urn:btih:${t.infohash}&dn=${Uri.encodeComponent(t.name)}';
    }
    final torrentUrl = t.torrentUrl;
    if (torrentUrl != null && torrentUrl.isNotEmpty) {
      try {
        return await TorrentFileService.magnetFromTorrentUrl(
          torrentUrl,
          fallbackName: t.name,
        );
      } catch (_) {
        return torrentUrl; // last resort (RD can still consume an http .torrent)
      }
    }
    return null;
  }

  static String _label(String provider) =>
      CloudProviderPresentation.label(provider);

  /// Two-letter provider glyph for the Pipeline loader's provider chip.
  static String _providerCode(String provider) =>
      CloudProviderPresentation.code(provider);

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
      hasCacheCheck: PlaybackServiceDispatch.hasCacheCheck(provider),
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
  static void _showLoading(BuildContext context, String provider, String name) {
    DebridLoadingOverlay.showForPlaybackId(
      context,
      provider,
      name,
      unknownLabel: _label,
    );
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }
}

typedef _Resolved = CloudPlaybackResult;

/// Mutable flag the catalog-play flow polls to abort when the user taps Cancel
/// on the poster loading mask (the mask dismisses itself; the flow just stops).
class _PlaybackCancelToken {
  bool cancelled = false;
}
