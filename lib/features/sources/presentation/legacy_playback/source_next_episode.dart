import 'dart:async';

import 'package:debrify/features/sources/application/source_candidate_checks.dart';
import 'package:debrify/features/sources/data/automatic_source_bindings.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/source_selection_diagnostics.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:flutter/material.dart';

final class SourceNextEpisode {
  const SourceNextEpisode._();

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
  static Future<void> Function(Map<String, dynamic>)? nextEpisodeHandlerFor(
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
      await TorrentPlaybackService.playFromSelection(
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
    final bound = (await SeriesSourceService.getSources(imdbId))
        .where(
          (source) => SourceCandidateChecks.bindingMatchesMeta(source, meta),
        )
        .toList();
    if (!context.mounted || !sourceBindings.isCurrent) return;
    if (bound.isNotEmpty && meta.season != null && meta.episode != null) {
      final played = await TorrentPlaybackService.playViaBound(
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
    await TorrentPlaybackService.playAddonStream(
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
}
