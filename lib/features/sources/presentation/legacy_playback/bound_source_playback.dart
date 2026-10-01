import 'dart:async';

import 'package:debrify/features/sources/application/source_candidate_checks.dart';
import 'package:debrify/features/sources/application/source_candidate_ranking.dart';
import 'package:debrify/features/sources/application/source_probing.dart';
import 'package:debrify/features/sources/application/source_provider_config.dart';
import 'package:debrify/features/sources/data/automatic_source_bindings.dart';
import 'package:debrify/features/sources/data/curated_source_search.dart';
import 'package:debrify/features/sources/data/source_acquisition_cleanup.dart';
import 'package:debrify/features/sources/data/source_magnet.dart';
import 'package:debrify/features/sources/data/source_movie_fetcher.dart';
import 'package:debrify/features/sources/data/source_series_fetcher.dart';
import 'package:debrify/features/sources/data/source_single_episode.dart';
import 'package:debrify/features/sources/models/playback_cancel_token.dart';
import 'package:debrify/features/sources/models/resolved_source.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/bound_source_resolution.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_binding_actions.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_loading_overlays.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_player_launch.dart';
import 'package:debrify/models/playback_meta.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/alldebrid_service.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/services/failed_saved_source.dart';
import 'package:debrify/services/iptv_source_search.dart';
import 'package:debrify/services/media_server_service.dart';
import 'package:debrify/services/resolved_playback_link_cache.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/source_selection_diagnostics.dart';
import 'package:debrify/services/storage/quick_play_storage.dart';
import 'package:debrify/services/stream_url_validator.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/widgets/pipeline_loading_overlay.dart';
import 'package:flutter/material.dart';

final class BoundSourcePlayback {
  const BoundSourcePlayback._();

  /// Play a pinned source directly (no search). Tries each bound source in
  /// priority order; returns true once one plays. Self-heals a source that is
  /// confirmed dead/uncached (removes it) so the caller can fall back to search.
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
        .where(
          (s) => SourceProviderConfig.boundProviderSupported(s.debridService),
        )
        .toList();
    if (usable.isEmpty) return false;

    final firstProv = SourceProviderConfig.providerFromStored(
      usable.first.debridService,
    );
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
            final rules = await QuickPlayStorage.getQuickPlayRules(
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
                  SourceSeriesFetcher.seriesFetcherFor(
                    meta: meta,
                    provider: preferredProvider,
                  ) ??
                  SourceMovieFetcher.movieFetcherFor(
                    meta: meta,
                    provider: preferredProvider,
                  ),
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
            final originVideoId =
                await CuratedSourceSearch.originEpisodeVideoId(
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
            final rules = await QuickPlayStorage.getQuickPlayRules(
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
                    !SourceCandidateRanking.shouldPreflightDirectStream(
                      fresh,
                    ) ||
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
                  SourceSeriesFetcher.seriesFetcherFor(
                    meta: meta,
                    provider: preferredProvider,
                  ) ??
                  SourceMovieFetcher.movieFetcherFor(
                    meta: meta,
                    provider: preferredProvider,
                  ),
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
        final (r, hint) = await BoundSourceResolution.resolveLocalBound(
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

      final prov = SourceProviderConfig.providerFromStored(
        source.debridService,
      );
      final nativeCloud = source.isProviderNativeCloud;
      final t = nativeCloud
          ? null
          : BoundSourceResolution.torrentFromSource(source);
      ResolvedSource? res;
      // Default reason if this attempt fails without a more specific one
      // (no magnet, empty play URL, not-cached, transient error) — Home's
      // generic wording. Overwritten below when we know more.
      fallbackHint =
          'Saved source is no longer available. Falling back to search.';
      try {
        final ResolvedSource? r;
        if (nativeCloud) {
          r = await BoundSourceResolution.resolveProviderNativeBound(
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
              : (SourceSeriesFetcher.seriesFetcherFor(
                      meta: meta,
                      provider: prov,
                    ) ??
                    SourceMovieFetcher.movieFetcherFor(
                      meta: meta,
                      provider: prov,
                    )),
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
    if (fallbackHint != null && context.mounted) {
      SourceLoadingOverlays.snack(context, fallbackHint);
    }
    return false;
  }
}
