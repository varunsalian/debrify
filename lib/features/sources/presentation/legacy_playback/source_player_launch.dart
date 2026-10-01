import 'dart:async';

import 'package:debrify/features/sources/application/source_provider_config.dart';
import 'package:debrify/features/sources/data/automatic_source_bindings.dart';
import 'package:debrify/features/sources/data/source_binding_committer.dart';
import 'package:debrify/features/sources/data/source_playlist_resolver.dart';
import 'package:debrify/features/sources/models/resolved_source.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/deovr_launch.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_next_episode.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_player_args.dart';
import 'package:debrify/models/playback_meta.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/source_playlist_resolver.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/source_selection_diagnostics.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/widgets/pipeline_loading_overlay.dart';
import 'package:flutter/material.dart';

final class SourcePlayerLaunch {
  const SourcePlayerLaunch._();

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
  static SourcePlaylistResolve lazyProviderResolver(
    SourceBindingCommitter committer,
  ) => resolverFor(null, committer);

  /// Launch the player. Passes the full source list + a resolver (so the player
  /// shows the in-player "Sources" switcher) and content metadata (so Continue
  /// Watching, subtitles and the Episodes button work) — matching Home.
  static Future<void> launch(
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
          (meta == null &&
              r.hasPlaylist &&
              SourcePlayerArgs.isSeriesPlaylist(r.playlist!))
          ? PlaylistViewMode.series
          : null;
      // VR hand-off (parity with the old search screen): for a single video file
      // played from KEYWORD search (meta == null), when the user's VR mode says
      // so, play in DeoVR instead of the in-app player. Scoped to keyword so this
      // shared launcher doesn't newly divert catalog board plays. Packs keep the
      // normal player (DeoVR takes one video).
      if (meta == null &&
          !r.hasPlaylist &&
          await DeovrLaunch.shouldUseDeoVR(title)) {
        // DeoVR runs its own dialog flow — drop the loader before it.
        overlay?.dismiss();
        if (!context.mounted || !sourceBindings.isCurrent) return;
        await DeovrLaunch.launchWithDeoVR(
          context,
          videoUrl: r.playUrl!,
          filename: title,
        );
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
          : validatedLaunchCommitter(
              provider,
              meta,
              sourceBindings: sourceBindings,
            );
      final args = SourcePlayerArgs.playerArgs(
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
                  ? lazyProviderResolver(committer)
                  : resolverFor(resolverProvider, committer))
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
      final nextEpisodeHandler = SourceNextEpisode.nextEpisodeHandlerFor(
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

  /// Builds the in-player source-switch resolver: given another [Torrent] the
  /// user picked, add it to [provider] and return its playlist (so switching
  /// sources works without leaving the player).
  static SourcePlaylistResolve resolverFor(
    String? provider,
    SourceBindingCommitter committer,
  ) => SourcePlaylistResolver(
    owner: committer.bindings.owner,
    provider: provider,
    canContinue: () => committer.isCurrent,
    chooseProvider: (active) =>
        SourceProviderConfig.defaultConfiguredProvider(canContinue: active),
  ).resolve;

  static SourceBindingCommitter validatedLaunchCommitter(
    String provider,
    PlaybackMeta? meta, {
    required AutomaticSourceBindings sourceBindings,
  }) => SourceBindingCommitter(
    bindings: sourceBindings,
    meta: meta,
    provider: provider,
    chooseProvider: (active) =>
        SourceProviderConfig.defaultConfiguredProvider(canContinue: active),
  );

  @visibleForTesting
  static Future<void> Function(Torrent) validatedSourceCommitterForTesting(
    String provider,
    PlaybackMeta? meta,
  ) => validatedLaunchCommitter(
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
    chooseProvider: (active) =>
        SourceProviderConfig.defaultConfiguredProvider(canContinue: active),
  );
}
