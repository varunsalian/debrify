import 'dart:async';

import 'package:debrify/features/sources/application/source_candidate_ranking.dart';
import 'package:debrify/features/sources/application/source_filter_ladder.dart';
import 'package:debrify/features/sources/data/recovery_source_resolution.dart';
import 'package:debrify/features/sources/data/source_series_fetcher.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/automatic_play_selection.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/manual_source_activation.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/provider_accepted_actions.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_binding_actions.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_loading_overlays.dart';
import 'package:flutter/material.dart';

import '../features/sources/data/automatic_source_bindings.dart';
import '../features/sources/data/manual_source_preparation.dart';
import '../models/playback_meta.dart';
import '../models/quick_play_rules.dart';
import '../models/torrent.dart';
import '../screens/video_player/models/playlist_entry.dart';
import '../utils/filter_ladder.dart';
import '../widgets/pipeline_loading_overlay.dart';
import 'profiles/profile_session_memory.dart';
import 'series_source_fetcher.dart';
import 'series_source_service.dart';

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

  static Future<void> activateTorrent(
    BuildContext context,
    Torrent torrent, {
    bool forcePlay = false,
    PlaybackMeta? meta,
    List<Torrent>? sources,
    int sourceIndex = 0,
    String searchKeyword = '',
    AutomaticSourceBindings? sourceBindings,
  }) => ManualSourceActivation.activateTorrent(context, torrent, forcePlay: forcePlay, meta: meta, sources: sources, sourceIndex: sourceIndex, searchKeyword: searchKeyword, sourceBindings: sourceBindings);

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
