import 'dart:async';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_dependencies.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_focus_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_menus.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_metadata_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_metadata_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_playback_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_resume_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_root_layout.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_tracking_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_tracking_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_trailer_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_trailer_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_watchlist_actions.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/widgets/detail/detail_model.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MergedDetailModelFactory {
  final MergedDetailDependencies _deps;
  MergedDetailModelFactory(this._deps);
  DetailFocusCoordinator get _focusCoordinator => _deps.focusCoordinator();
  StremioMeta get _item => _deps.presentedItem();
  MetadataPreferences get metadataPreferences => _deps.metadataPreferences();
  bool get mounted => _deps.mounted();
  void Function(VoidCallback) get setState => _deps.setState;
  MergedDetailFocusState get _f => _deps.parts.focusState;
  MergedDetailMenus get _mn => _deps.parts.menus;
  MergedDetailMetadataActions get _ma => _deps.parts.metadataActions;
  MergedDetailMetadataState get _m => _deps.parts.metadataState;
  MergedDetailPlaybackActions get _pl => _deps.parts.playbackActions;
  MergedDetailResumeActions get _ra => _deps.parts.resumeActions;
  MergedDetailRootLayout get _ro => _deps.parts.rootLayout;
  MergedDetailTrackingActions get _ta => _deps.parts.trackingActions;
  MergedDetailTrackingState get _k => _deps.parts.trackingState;
  MergedDetailTrailerActions get _tr => _deps.parts.trailerActions;
  MergedDetailTrailerState get _t => _deps.parts.trailerState;
  MergedDetailWatchlistActions get _wa => _deps.parts.watchlistActions;

  /// Everything the alternate layouts render, rebuilt with the screen so every
  /// load, refresh and tracker round-trip reaches them unchanged.
  ///
  /// Layouts are stateless with respect to data — they own only focus, scroll
  /// The bound sources behind Showcase's Sources band.
  ///
  /// A SharedPreferences read plus a JSON decode — no network — which is what
  /// lets the band paint on open. Reloaded after the source manager closes and
  /// on playback return, or it goes stale the moment anyone binds anything.
  List<SeriesSource> boundSources = const [];

  /// Called from every path that can change a binding — the source manager,
  /// the app-action menu, and playback return. A band that only refreshes on
  /// one of the three is stale the first time someone uses another.
  Future<void> loadBoundSources() async {
    final imdb = _item.imdbId;
    if (imdb == null || imdb.isEmpty) return;
    final list = await SeriesSourceService.getSources(imdb);
    if (!mounted) return;
    setState(() => boundSources = list);
  }

  /// and tab state.
  DetailModel buildDetailModel() {
    return DetailModel(
      item: _item,
      metadataPreferences: metadataPreferences,
      isMovie: _ro.isMovie,
      isTelevision: _deps.isTelevision(),
      // Signal keeps the poster-extracted accent, which is what ships today.
      // A fixed-palette theme (Noir's white, Phosphor's amber) would be
      // contaminated by it, so it uses its own.
      accent: _ro.theme.useArtworkAccent ? _m.accent : _ro.theme.accent,
      imdbExtra: _m.imdbExtra,
      parentsGuide: _m.parentsGuide,
      recommendations: _m.recommendations ?? const [],
      openingDataReady: _m.showcaseOpeningDataReady,
      primaryLabel: _ra.primaryLabel,
      primaryBusy: _ra.primaryBusy,
      sourceCount: _deps.boundSourceCount()?.call(_deps.item()) ?? 0,
      boundSources: boundSources,
      hasTrailer: _t.trailerYtId != null,
      trailerBusy: _t.trailerResolving || _t.trailerLoading,
      trailerPlaying: _t.trailerAmbientPlaying,
      hasTrakt: _mn.traktOnlyMenuOptions.isNotEmpty,
      traktTracked: _ta.traktTracked,
      traktLabel: _ta.traktPillLabel,
      traktRating: _k.traktStatus?.rating,
      hasSimkl: _mn.menuOptionsSimkl.isNotEmpty,
      simklTracked: _ta.simklTracked,
      simklLabel: _ta.simklPillLabel,
      simklRating: _k.simklStatus?.rating,
      hasMdblist: _mn.menuOptionsMdblist.isNotEmpty,
      mdblistTracked: _ta.mdblistTracked,
      mdblistLabel: _ta.mdblistPillLabel,
      mdblistRating: _k.mdblistStatus?.rating,
      showPrimary: _deps.showQuickPlay(),
      onPrimary: _pl.playPrimary,
      onPrimaryLongPress:
          ((_ro.isMovie && _deps.onBrowse() != null) ||
              (!_ro.isMovie && _deps.onBrowsePrimaryEpisodeSources() != null))
          ? _pl.browsePrimarySources
          : null,
      // A movie browses the full source list the host supplies; a series
      // browses season packs — the same search the More menu's "Search
      // season packs" row opens, promoted to a first-class button. Gated on
      // that row actually being in the menu so the button never mounts for a
      // host that didn't offer the action.
      onBrowse: _ro.isMovie
          ? _deps.onBrowse()
          : (_deps.onTraktAction() != null &&
                _mn.appMenuOptions.any(
                  (o) => o.action == TraktItemMenuAction.searchPacks,
                ))
          ? () => _deps.onTraktAction()!(TraktItemMenuAction.searchPacks)
          : null,
      onTrailer: _tr.playTrailer,
      onSelectSource: _deps.onSelectSource() == null
          ? null
          : () async {
              await _deps.onSelectSource()!(_deps.item());
              if (mounted) setState(() {});
            },
      onMetadataExplore: _ma.metadataExploreAction,
      onAppMenu:
          (_mn.appMenuOptions.isNotEmpty && _deps.onTraktAction() != null)
          ? _mn.showAppActionsMenu
          : null,
      onTraktMenu: _deps.onTraktAction() != null
          ? _mn.showQuickActionsMenu
          : null,
      onSimklMenu: _deps.onSimklAction() != null
          ? _mn.showSimklQuickActionsMenu
          : null,
      onMdblistMenu: _deps.onMdblistAction() != null
          ? _mn.showMdblistQuickActionsMenu
          : null,
      inMyWatchlist: _k.inMyWatchlist,
      onToggleMyWatchlist: _wa.supportsMyWatchlist
          ? _wa.toggleMyWatchlist
          : null,
      // Both trackers behind one affordance, for a layout whose action row has
      // no room for two branded pills. Whichever single service is configured
      // opens directly; with both, the app menu is the chooser that already
      // lists them.
      // Null when neither service is configured, or the layout mounts a `+`
      // that focuses and does nothing. There is no combined sheet to open —
      // `_showAppActionsMenu` is the APP-action list, not a tracker chooser —
      // so with both configured this opens Trakt's, and Simkl stays reachable
      // through the More button beside it.
      // Gated on whether a tracker is actually CONNECTED, not on whether the
      // host passed a callback — the home screen always passes the Trakt one,
      // so a callback test mounts a `+` that focuses and does nothing for
      // anyone who has not connected Trakt.
      //
      // With both connected this opens Trakt's sheet and Simkl stays reachable
      // from the More button beside it; there is no combined sheet to open,
      // and `_showAppActionsMenu` is the APP-action list, not a chooser.
      onTrackers:
          (_mn.traktOnlyMenuOptions.isNotEmpty && _deps.onTraktAction() != null)
          ? _mn.showQuickActionsMenu
          : (_mn.menuOptionsSimkl.isNotEmpty && _deps.onSimklAction() != null
                ? _mn.showSimklQuickActionsMenu
                : (_mn.menuOptionsMdblist.isNotEmpty &&
                          _deps.onMdblistAction() != null
                      ? _mn.showMdblistQuickActionsMenu
                      : null)),
      // Only when Trakt already took the first slot; otherwise Simkl IS the
      // first slot above and this would mount the same sheet twice.
      onTrackersSecondary:
          (_mn.traktOnlyMenuOptions.isNotEmpty &&
              _deps.onTraktAction() != null &&
              _mn.menuOptionsSimkl.isNotEmpty &&
              _deps.onSimklAction() != null)
          ? _mn.showSimklQuickActionsMenu
          : (((_mn.traktOnlyMenuOptions.isNotEmpty &&
                        _deps.onTraktAction() != null) ||
                    (_mn.menuOptionsSimkl.isNotEmpty &&
                        _deps.onSimklAction() != null)) &&
                _mn.menuOptionsMdblist.isNotEmpty &&
                _deps.onMdblistAction() != null)
          ? _mn.showMdblistQuickActionsMenu
          : null,
      onTrackersTertiary:
          (_mn.traktOnlyMenuOptions.isNotEmpty &&
              _deps.onTraktAction() != null &&
              _mn.menuOptionsSimkl.isNotEmpty &&
              _deps.onSimklAction() != null &&
              _mn.menuOptionsMdblist.isNotEmpty &&
              _deps.onMdblistAction() != null)
          ? _mn.showMdblistQuickActionsMenu
          : null,
      // There is no per-source host API, so a card in the Sources band and the
      // "Find sources" tile both land on the title-level manager — and the
      // band reloads afterwards, since binding is exactly what changes it.
      onManageSources: _deps.onSelectSource() == null
          ? null
          : () async {
              await _deps.onSelectSource()!(_deps.item());
              if (!mounted) return;
              setState(() {});
              await loadBoundSources();
            },
      onRecommendationTap: _deps.onRecommendationTap() == null
          ? null
          : _m.openMetadataRecommendation,
      onAmbientStill: (url) {
        if (!mounted || _f.focusedStillUrl == url) return;
        setState(() => _f.focusedStillUrl = url);
      },
      onDepth: (deep) {
        if (!mounted || _f.bodyDeep == deep) return;
        setState(() => _f.bodyDeep = deep);
      },
      focus: _focusCoordinator,
    );
  }
}
