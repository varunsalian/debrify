import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/advanced_search_selection.dart';
import '../../models/stremio_addon.dart';
import '../search/title_opener.dart';
import '../search/selection_playback_owner.dart';
import '../../services/iptv_cw_router.dart';
import '../../services/main_page_bridge.dart';
import '../../services/series_source_service.dart';
import '../../services/local_series_completion_service.dart';
import '../../services/torrent_playback_service.dart';
import '../../services/playback/catalog_play_resolver.dart';
import '../../widgets/sources/source_binding_dialogs.dart';
import '../search/source_binding_routes.dart';
import '../../services/mdblist/mdblist_menu_helpers.dart';
import '../../widgets/trakt/trakt_menu_helpers.dart';
import '../../services/simkl/simkl_menu_helpers.dart';
import '../episodes_screen.dart';
import '../stremio_tv/widgets/stremio_tv_catalog_picker_dialog.dart';
import 'search_sources.dart' show buildSearchSources;
import 'search_content_session.dart';

/// Shared content actions; controller data comes from the session, not State.
/// The surface exposes only Flutter context, liveness and synchronous commit.
class SearchContentActions {
  SearchContentActions(this.session);
  final SearchContentSession session;
  BuildContext get context => session.surface.context;
  bool get mounted => session.surface.mounted;
  final selectionPlayback = SelectionPlaybackOwner();
  late final selectionRoutes = SelectionPlaybackRoutes(
    readIsTelevision: () => session.options.isTelevision,
    refreshBoundSources: session.refreshBoundSources,
    refreshAfterPlayback: () => session.refreshAfterPlayback(),
  );
  late final CatalogPlayResolver resolver = CatalogPlayResolver(
    isTraktAuthenticated: () => session.isTraktAuthenticated,
    isSimklAuthenticated: () => session.isSimklAuthenticated,
    isMdblistAuthenticated: () => session.isMdblistAuthenticated,
    traktByImdb: session.cw.traktByImdb,
    imdbOf: session.imdbOf,
  );

  void openItem(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
    bool isMdblistSource = false,
    // Shared-element tag from the tapped board cell: the poster flies into the
    // detail page's backdrop. Null (non-board callers) = regular transition.
    String? heroTag,
    // For a series opened at a specific episode (Trakt Calendar): scroll the
    // episodes panel to this season/episode. Ignored by the movie/legacy paths.
    int? initialSeason,
    int? initialEpisode,
    // When set, switch back to this tab once the detail route closes — lets a
    // cross-tab opener (the Calendar) return the user to where they came from.
    int? returnToTabOnClose,
  }) {
    TitleOpener(
      getContext: () => context,
      isTelevision: () => session.options.isTelevision,
      mergedSeriesPage: () => session.mergedSeriesPage,
      pikpakOnly: () => session.pikpakOnly,
      cwIds: session.cw.cwIds,
      traktByImdb: session.cw.traktByImdb,
      mdblistByImdb: session.cw.mdblistByImdb,
      simklByImdb: session.cw.simklByImdb,
      isTraktAuthenticated: () => session.isTraktAuthenticated,
      isSimklAuthenticated: () => session.isSimklAuthenticated,
      isMdblistAuthenticated: () => session.isMdblistAuthenticated,
      imdbOf: session.imdbOf,
      isBound: session.isBound,
      boundCountFor: session.boundCountFor,
      onActiveAddon: (id) => selectionPlayback.activeAddonId = id,
      resolveResumeInfo: resolveResumeInfo,
      onCatalogPlay: onCatalogPlay,
      onCatalogBrowse: onCatalogBrowse,
      onItemSelected: browseSelection,
      onQuickPlay: playSelection,
      onSelectSource: handleEditOrSelectSource,
      onDetailQuickAction: handleDetailQuickAction,
      onDetailSimklQuickAction: handleDetailSimklQuickAction,
      onDetailMdblistQuickAction: handleDetailMdblistQuickAction,
      onLoaderArt: selectionPlayback.adoptDetailArt,
      getRecommendations: session.stremio.getRecommendations,
      fetchMetaDetails: session.stremio.fetchMetaDetails,
      onAfterPlayback: session.refreshAfterPlayback,
      onRefreshTraktAuth: session.refreshTraktAuthState,
      onRefreshSimklAuth: session.refreshSimklAuthState,
      onRefreshMdblistAuth: session.refreshMdblistAuthState,
    ).open(
      item,
      addon,
      isTraktSource: isTraktSource,
      isMdblistSource: isMdblistSource,
      heroTag: heroTag,
      initialSeason: initialSeason,
      initialEpisode: initialEpisode,
      returnToTabOnClose: returnToTabOnClose,
    );
  }

  Future<void> handleDetailQuickAction(
    StremioMeta item,
    StremioAddon addon,
    TraktItemMenuAction action, {
    required bool inCw,
    String? imdb,
    // Set by the merged detail sheet's inline rating strip, which already knows
    // the score — skips the rating dialog rather than asking twice.
    int? presetRating,
  }) async {
    if (action == TraktItemMenuAction.removeFromPlayback) {
      if (imdb != null) await handleContinueDetailAction(action, imdb);
      return;
    }
    if (action == TraktItemMenuAction.removeFromTraktPlayback) {
      if (imdb != null) await removeFromTraktContinueWatching(imdb);
      return;
    }
    await handleTraktMenuAction(
      context,
      item,
      action,
      // "Select Source" when nothing is bound → straight to the picker; when a
      // source is already bound → the rich edit dialog (list / reorder / remove
      // / add). Matches the catalog/aggregated detail flow.
      onSelectSource: openBindSources,
      onEditSource: handleEditOrSelectSource,
      onPlayRandomEpisode: (m) => playRandomEpisodeFromDetail(m, addon),
      onSearchPacks: searchPacksFromDetail,
      onAddToStremioTv: addToStremioTvFromDetail,
      presetRating: presetRating,
    );
    // A Trakt watched-state change moves a title in/out of Continue Watching,
    // so reload the board's Trakt rows — otherwise the board is stale when the
    // user backs out of the detail (old home reloads its list after these).
    // Skipped on the dedicated Search tab, which never renders those rows.
    if (mounted &&
        !session.options.searchMode &&
        (action == TraktItemMenuAction.markWatched ||
            action == TraktItemMenuAction.markUnwatched)) {
      session.cw.loadTraktContinueWatching(refreshBound: false);
    }
  }

  Future<void> handleDetailSimklQuickAction(
    StremioMeta item,
    SimklItemMenuAction action, {
    int? presetRating,
  }) async {
    await handleSimklMenuAction(
      context,
      item,
      action,
      presetRating: presetRating,
    );
    // Any status change can add/remove a title from the Simkl CW rows: On Hold
    // and remove/completed/dropped take it OFF, while Watching makes a series
    // newly eligible as an "up next" card. So reload the rows on every one that
    // shifts CW membership. Skipped on the dedicated Search tab (no rows there).
    if (mounted &&
        !session.options.searchMode &&
        (action == SimklItemMenuAction.removeFromContinueWatching ||
            action == SimklItemMenuAction.removeFromList ||
            action == SimklItemMenuAction.moveToCompleted ||
            action == SimklItemMenuAction.moveToDropped ||
            action == SimklItemMenuAction.moveToOnHold ||
            action == SimklItemMenuAction.moveToWatching)) {
      session.cw.loadSimklContinueWatching(refreshBound: false);
    }
  }

  Future<void> handleDetailMdblistQuickAction(
    StremioMeta item,
    MdblistItemMenuAction action, {
    int? presetRating,
  }) async {
    if (action == MdblistItemMenuAction.removeFromContinueWatching) {
      await session.cw.removeMdblistCwItem(item, imdbOf: session.imdbOf);
      return;
    }
    await handleMdblistMenuAction(
      context,
      item,
      action,
      presetRating: presetRating,
    );
    if (!mounted || session.options.searchMode) return;
    if (action == MdblistItemMenuAction.markWatched ||
        action == MdblistItemMenuAction.markUnwatched ||
        action == MdblistItemMenuAction.drop ||
        action == MdblistItemMenuAction.restore) {
      await session.cw.loadMdblistContinueWatching(refreshBound: false);
    }
  }

  Future<void> handleEditOrSelectSource(StremioMeta item) async {
    final imdb = session.imdbOf(item);
    final bound = imdb == null
        ? const <SeriesSource>[]
        : await SeriesSourceService.getSources(imdb);
    if (!mounted) return;
    if (bound.isNotEmpty) {
      await showEditSourceDialog(item, bound);
    } else {
      await showAddSourcePicker(item);
    }
  }

  Future<void> showEditSourceDialog(
    StremioMeta item,
    List<SeriesSource> initial,
  ) => SourceBindingDialogs.showEdit(
    context: context,
    item: item,
    cloudRoutes: SourceBindingRoutes.cloud,
    initial: initial,
    onRefreshBound: session.refreshBoundSources,
    onTorrentSearch: openBindSources,
    onKeywordSearch: openKeywordBind,
    onSnack: snack,
    isHostMounted: () => mounted,
  );

  Future<void> showAddSourcePicker(StremioMeta item) =>
      SourceBindingDialogs.showAdd(
        context: context,
        item: item,
        cloudRoutes: SourceBindingRoutes.cloud,
        onRefreshBound: session.refreshBoundSources,
        onTorrentSearch: openBindSources,
        onKeywordSearch: openKeywordBind,
        onSnack: snack,
        isHostMounted: () => mounted,
      );

  Future<void> addToStremioTvFromDetail(StremioMeta item) async {
    final result = await StremioTvCatalogPickerDialog.show(context, item: item);
    if (!mounted || result == null) return;
    snack(result.message);
  }

  void searchPacksFromDetail(StremioMeta item) {
    final imdb = session.imdbOf(item);
    if (imdb == null) {
      snack('No IMDb match to find packs for "${item.name}".');
      return;
    }
    browseSelection(
      AdvancedSearchSelection(
        imdbId: imdb,
        isSeries: true,
        title: item.name,
        year: item.year,
        contentType: item.type,
        posterUrl: item.poster,
      ),
    );
  }

  Future<StremioAddon?> metaAddonFor(StremioAddon preferred) async {
    if (preferred.resources.contains('meta') && preferred.baseUrl.isNotEmpty) {
      return preferred;
    }
    for (final a in await session.stremio.getEnabledAddons()) {
      if (a.resources.contains('meta') && a.baseUrl.isNotEmpty) return a;
    }
    return null;
  }

  Future<void> playRandomEpisodeFromDetail(
    StremioMeta item,
    StremioAddon addon,
  ) async {
    final imdb = session.imdbOf(item);
    if (imdb == null) {
      snack('No IMDb match to pick an episode for "${item.name}".');
      return;
    }
    final metaAddon = await metaAddonFor(addon);
    // If we fell back to a different meta addon than the item's origin, its
    // content id won't match — query by IMDb id instead of the origin's id.
    final contentId = (metaAddon != null && metaAddon.id == addon.id)
        ? item.id
        : imdb;
    final videos = metaAddon == null
        ? null
        : await session.stremio.fetchSeriesMeta(metaAddon, contentId);
    if (!mounted) return;
    if (videos != null) {
      unawaited(
        LocalSeriesCompletionService.instance.recordRawEpisodeInventory(
          imdbId: imdb,
          seriesTitle: item.name,
          videos: videos,
        ),
      );
    }

    final episodes = <({int season, int episode})>[];
    for (final v in videos ?? const <Map<String, dynamic>>[]) {
      final sRaw = v['season'];
      final s = sRaw is num ? sRaw.toInt() : null;
      if (s == null || s <= 0) continue; // skip specials (season 0)
      final eRaw = v['number'] ?? v['episode'];
      final e = eRaw is num ? eRaw.toInt() : null;
      if (e == null) continue;
      episodes.add((season: s, episode: e));
    }
    if (episodes.isEmpty) {
      snack("Couldn't load episodes for \"${item.name}\".");
      return;
    }

    final pick = episodes[Random().nextInt(episodes.length)];
    playSelection(
      AdvancedSearchSelection(
        imdbId: imdb,
        isSeries: true,
        title: item.name,
        year: item.year,
        season: pick.season,
        episode: pick.episode,
        contentType: item.type,
        posterUrl: item.poster,
      ),
    );
  }

  Future<void> onCatalogPlay(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
    bool isMdblistSource = false,
    // Merged series page: episodes are already shown inline, so a no-IMDb
    // series must NOT fall back to pushing a standalone EpisodesScreen (that
    // would stack a duplicate episode list on top). It resolves the resume
    // episode against the raw catalog id and plays via the addon /stream path.
    bool skipEpisodeFallback = false,
    // Merged detail Resume: honour Trakt's paused position for ANY authenticated
    // title (not just Trakt-CW-sourced ones), so Play matches the Trakt-first
    // label from [resolveResumeInfo]. Off elsewhere (Home/row quick-play keep
    // their local-vs-Trakt-CW split untouched).
    bool preferTraktResume = false,
    // The episode the pressed button was promising, when the caller had already
    // resolved one (merged detail). It wins over [_reconcileSeriesResume]: that
    // reconciler only reads resume/CW positions, while the merged page's episode
    // engine also advances off watched state. A show whose progress lives in a
    // tracker's WATCHED list but not its continue-watching list reconciles to the
    // empty-candidates fallback (S01E01) while the label correctly reads S1E2 —
    // and Play would then start the pilot under a "Resume · S1E2" button.
    ({bool started, int season, int episode})? promisedTarget,
    // Primary-button hold: run the exact same target/scrobble reconciliation,
    // but hand the resulting selection to the manual Sources page instead of
    // auto-playing it. Used for series; movies already have a direct Sources
    // callback and do not need to enter this resolver.
    bool browseSourcesOnly = false,
  }) async {
    // The loader's backdrop/logo/meta line for this title. Captured here (the
    // one play entry point that still holds the catalog meta) and read back in
    // [SelectionPlaybackOwner.metaFor], which only ever sees a selection.
    selectionPlayback.captureCatalogArt(item);
    var cancelled = false;
    final resolving = preferTraktResume
        ? TorrentPlaybackService.showResolvingOverlay(
            context,
            meta: PlaybackMeta.catalog(
              imdbId: item.effectiveImdbId,
              contentType: item.type,
              title: item.name,
              posterUrl: item.poster,
              year: item.year,
              addonId: addon.id,
              art: selectionPlayback.pendingArt,
            ),
            title: item.name,
            onCancel: () => cancelled = true,
          )
        : null;
    Future<void> launch(AdvancedSearchSelection selection) async {
      debugPrint(
        '[SeriesResume] ${browseSourcesOnly ? 'sources-open' : 'play-launch'} '
        'title="${selection.title}" '
        'id=${selection.imdbId} season=${selection.season} '
        'episode=${selection.episode} trakt=${selection.traktSource} '
        'traktPct=${selection.traktProgressPercent} '
        'simkl=${selection.simklSource} '
        'simklPct=${selection.simklProgressPercent} '
        'mdblist=${selection.mdblistSource} '
        'mdblistPct=${selection.mdblistProgressPercent}',
      );
      resolving?.dismiss();
      if (cancelled) return;
      if (browseSourcesOnly) {
        browseSelection(selection);
      } else {
        await playSelection(selection);
      }
    }

    try {
      // Set the active addon before any early return so a movie play carries the
      // right addon id into meta.addonId (addon-stream resume/next), instead of a
      // stale one left over from a previously-browsed series.
      selectionPlayback.activeAddonId = addon.id;
      final decision = await resolver.resolvePlay(
        item,
        addon,
        isTraktSource: isTraktSource,
        isMdblistSource: isMdblistSource,
        skipEpisodeFallback: skipEpisodeFallback,
        preferTraktResume: preferTraktResume,
        promisedTarget: promisedTarget,
        browseSourcesOnly: browseSourcesOnly,
        isCancelled: () => cancelled || !mounted,
      );
      switch (decision) {
        case CatalogPlayLaunch(:final selection):
          await launch(selection);
        case CatalogPlayOpenEpisodes():
          if (!cancelled) {
            openEpisodes(
              item,
              addon,
              isTraktSource: isTraktSource,
              isMdblistSource: isMdblistSource,
            );
          }
        case CatalogPlayAborted():
          break;
      }
    } finally {
      resolving?.dismiss();
    }
  }

  Future<({bool started, int? season, int? episode})> resolveResumeInfo(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
    bool isMdblistSource = false,
  }) => resolver.resolveResumeInfo(
    item,
    addon,
    isTraktSource: isTraktSource,
    isMdblistSource: isMdblistSource,
    isCancelled: () => !mounted,
  );

  void onCatalogBrowse(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
    bool isMdblistSource = false,
  }) {
    final decision = resolver.onCatalogBrowse(
      item,
      isTraktSource: isTraktSource,
      isMdblistSource: isMdblistSource,
    );
    if (decision.openEpisodes) {
      openEpisodes(
        item,
        addon,
        isTraktSource: isTraktSource,
        isMdblistSource: isMdblistSource,
      );
    } else if (decision.selection != null) {
      browseSelection(decision.selection!);
    }
  }

  void openEpisodes(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
    bool isMdblistSource = false,
  }) {
    selectionPlayback.activeAddonId = addon.id;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            settings: const RouteSettings(name: kEpisodesRouteName),
            builder: (_) => EpisodesScreen(
              show: item,
              addon: addon,
              isTelevision: session.options.isTelevision,
              isTraktSource: isTraktSource,
              isMdblistSource: isMdblistSource,
              // EpisodesScreen pops itself (and the detail route) before firing
              // these, so we're back on the Search screen when they run.
              onQuickPlay: playSelection,
              onItemSelected: browseSelection,
              // "Select Source" button: manage/pin sources via the same picker
              // the detail screen uses (edit dialog when already bound, else the
              // Torrent Search / Local / RD / TorBox picker) for a consistent
              // entry point.
              boundSourceCount: session.boundCountFor,
              onSelectSource: handleEditOrSelectSource,
            ),
          ),
        )
        .then((_) {
          // EpisodesScreen can mark watched / play; its plays route through
          // playSelection (which clears too), but marks don't — never let a
          // pre-visit reconciled answer survive the trip.
          resolver.clearSeriesResumeCache();
          session.refreshBoundSources();
        });
  }

  void openBindSources(StremioMeta show) {
    final imdb = session.imdbOf(show);
    if (imdb == null) {
      snack('No IMDb match to pin a source for "${show.name}".');
      return;
    }
    final sel = AdvancedSearchSelection(
      imdbId: imdb,
      isSeries: show.type == 'series',
      title: show.name,
      year: show.year,
      contentType: show.type,
      posterUrl: show.poster,
    );
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => buildSearchSources(
              selection: sel,
              meta: selectionPlayback.metaFor(sel),
              isTelevision: session.options.isTelevision,
              bindMode: true,
            ),
          ),
        )
        .then((_) => session.refreshBoundSources());
  }

  void openKeywordBind(StremioMeta show) {
    final imdb = session.imdbOf(show);
    if (imdb == null) {
      snack('No IMDb match to pin a source for "${show.name}".');
      return;
    }
    final isSeries = show.type == 'series';
    final seed = isSeries
        ? '${show.name} complete'
        : (show.year != null && show.year!.isNotEmpty
              ? '${show.name} ${show.year}'
              : show.name);
    final sel = AdvancedSearchSelection(
      imdbId: imdb,
      isSeries: isSeries,
      title: show.name,
      year: show.year,
      contentType: show.type,
      posterUrl: show.poster,
    );
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => buildSearchSources(
              selection: sel,
              meta: selectionPlayback.metaFor(sel),
              isTelevision: session.options.isTelevision,
              bindMode: true,
              keywordSeed: seed,
            ),
          ),
        )
        .then((_) => session.refreshBoundSources());
  }

  Future<void> playSelection(AdvancedSearchSelection sel) async {
    // Playback is about to change every resume signal — never let a
    // pre-playback reconciled answer survive into the post-playback reads.
    resolver.clearSeriesResumeCache();
    // Row quick-play skips the detail page, so there's no detail route whose
    // pop can drive the post-playback refresh — this method has to do it. WHEN
    // it can depends on the player: the in-app route only completes the await
    // below once it pops (playback over, progress final), while an external
    // activity returns control immediately, still mid-launch. Latch which one
    // took the stream so a native/external launch doesn't fire a pointless
    // tracker refetch while the player is still opening — its real refresh
    // arrives via _onPlaybackReturned.
    var external = false;
    void onExternal() => external = true;
    MainPageBridge.addExternalPlayerLaunchListener(onExternal);
    try {
      await selectionPlayback.launch(context, sel, routes: selectionRoutes);
    } finally {
      MainPageBridge.removeExternalPlayerLaunchListener(onExternal);
    }
    if (!mounted) return;
    // The full refresh only when the in-app player has genuinely finished AND
    // the board is what's on screen. An external launch is still opening, and a
    // detail page / See-All on top owns the refresh through its own route
    // callback — the latch keeps that deferred pass aware playback happened, so
    // skipping here loses nothing and avoids refreshing an invisible board.
    await selectionPlayback.refreshAfterLaunch(
      // The delegated actual State.mounted guard above precedes this lazy read.
      // ignore: use_build_context_synchronously
      context,
      external: external,
      routes: selectionRoutes,
    );
  }

  void browseSelection(
    AdvancedSearchSelection sel, {
    // Set only by the Play-button hand-off: the press already said "play", so
    // the row the user picks must not re-ask via the post-torrent action.
    bool forcePlayOnTap = false,
  }) {
    // Every route into the manual list lands here — the Play-button hand-off,
    // the movie Sources button, and the episode long-press — so this is where
    // the episode the list will search is finally fixed.
    debugPrint(
      '[SeriesResume] picker-open title="${sel.title}" id=${sel.imdbId} '
      'target=S${sel.season}E${sel.episode} label="${sel.formattedLabel}"',
    );
    if (sel.imdbId.isEmpty) {
      snack('No IMDb match to find sources for "${sel.title}".');
      return;
    }
    selectionPlayback.browse(
      context,
      sel,
      routes: selectionRoutes,
      forcePlayOnTap: forcePlayOnTap,
    );
  }

  void snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> handleContinueDetailAction(
    TraktItemMenuAction action,
    String imdbId,
  ) async {
    if (action != TraktItemMenuAction.removeFromPlayback) return;
    await session.cw.handleContinueDetailAction(
      imdbId: imdbId,
      popDetail: () => Navigator.of(context).pop(),
    );
  }

  Future<void> removeFromTraktContinueWatching(
    String imdbId, {
    bool popDetail = true,
  }) =>
      session.cw.removeFromTraktContinueWatching(imdbId, popDetail: popDetail);

  void openSimklItem(StremioMeta item) {
    openItem(item, session.addonForContinue(item.sourceAddon?.id));
  }

  void playSimklItem(StremioMeta item) {
    onCatalogPlay(item, session.addonForContinue(item.sourceAddon?.id));
  }

  Future<void> removeSimklCwItem(StremioMeta item) async {
    await handleSimklMenuAction(
      context,
      item,
      SimklItemMenuAction.removeFromContinueWatching,
    );
    if (!mounted) return;
    await session.cw.loadSimklContinueWatching(refreshBound: false);
  }

  Future<void> openIptvCwItem(StremioMeta item) async {
    final entry = session.cw.iptvCwByKey[item.id];
    if (entry == null) return;
    session.playedSinceRefresh = true;
    await IptvCwRouter.open(
      context,
      entry,
      isTelevision: session.options.isTelevision,
    );
    if (!mounted) return;
    // Off-TV push() awaits to the pop; on TV the native-return hook
    // ([_onPlaybackReturned]) refreshes. Refresh here too for the in-app path
    // (series detail / in-app player) so a resumed position updates the shelf.
    await session.refreshAfterPlayback();
  }
}
