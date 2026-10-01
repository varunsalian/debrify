import 'dart:async';

import 'package:debrify/features/sources/application/source_provider_config.dart';
import 'package:debrify/features/sources/data/automatic_source_bindings.dart';
import 'package:debrify/features/sources/data/manual_source_preparation.dart';
import 'package:debrify/features/sources/presentation/direct_source_binding.dart';
import 'package:debrify/features/sources/presentation/iptv_source_binding.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_loading_overlays.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_provider_choice.dart';
import 'package:debrify/features/sources/presentation/local_source_binding.dart';
import 'package:debrify/features/sources/presentation/torrent_source_binding.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/direct_source_authorization.dart';
import 'package:debrify/services/local_bound_source_service.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/source_selection_diagnostics.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:flutter/material.dart';

final class SourceBindingActions {
  const SourceBindingActions._();

  /// Continue after a saved source resolved successfully but the real player
  /// rejected it before startup committed. [remainingSources] preserves the
  /// saved priority order and [_playViaBound] keeps its exact-episode guards;
  /// only after those candidates fail do we re-enter search below the binding
  /// gate so the rejected source cannot loop.
  static Future<void> recoverAfterBoundStartupFailure(
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
      final played = await TorrentPlaybackService.playViaBound(
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
    await TorrentPlaybackService.playFromSelection(
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
    pickProvider: () =>
        SourceProviderChoice.pickProvider(context, canContinue: canContinue),
    showLoading: (provider) => SourceLoadingOverlays.showLoading(
      context,
      provider,
      torrent.name,
    ).dismiss,
    prepare: (provider) =>
        preparation.prepare(provider, torrent, canContinue: canContinue),
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
    providerLabel: SourceProviderChoice.label,
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
    describe: (source) => AutomaticSourceBindings.describe(
      source,
      SeriesSource.iptvDirectService,
    ),
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
}
