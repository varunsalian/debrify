import 'package:flutter/material.dart';

import '../../../models/home_collection.dart';
import '../../../models/home_collection_rows.dart';
import '../../../models/stremio_addon.dart';
import '../../../screens/collections/collection_folder_screen.dart';
import '../../../widgets/see_all/discover_card_settings_scope.dart';
import '../../discover/models/discover_card_settings.dart';
import '../data/home_board_services.dart';
import 'home_board_section.dart';
import 'home_catalog_actions.dart';
import 'home_catalog_badges.dart';
import 'home_continuation_playback.dart';
import 'home_continuation_return.dart';
import 'home_continuation_section.dart';
import 'home_display_section.dart';
import 'home_integration_section.dart';
import 'home_item_actions.dart';
import 'home_see_all_navigation.dart';
import 'home_stage_rows.dart';

typedef HomeRowsNavigationDeps = ({
  BuildContext Function() context,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  bool Function() isTelevision,
  bool Function() searchMode,
  bool Function() discoverMode,
  StremioAddon Function() nativeAddon,
  Future<bool> Function() readMergedSeriesEnabled,
  // Reads Discover's current card flags; the controller stays with Discover.
  DiscoverCardSettings Function({required bool Function() isCurrent})
  readCardSettings,
});

/// Resolves a row's source and wires collection, See-All and handed-off detail routes.
class HomeRowsNavigation {
  HomeRowsNavigation(
    this._deps,
    this._boardSection,
    this._displaySection,
    this._catalogBadges,
    this._itemActions,
    this._catalogActions,
    this._integrations,
    this._continuationSection,
    this._continuationPlayback,
    this._continuationReturn,
  );
  final HomeRowsNavigationDeps _deps;
  final HomeBoardSection _boardSection;
  final HomeDisplaySection _displaySection;
  final HomeCatalogBadges _catalogBadges;
  final HomeItemActions _itemActions;
  final HomeCatalogActions _catalogActions;
  final HomeIntegrationSection _integrations;
  final HomeContinuationSection _continuationSection;
  final HomeContinuationPlayback _continuationPlayback;
  final HomeContinuationReturn _continuationReturn;

  /// Experimental flag: route series taps to the merged detail+episodes page.
  /// Loaded once on init; movies and the flag-off path keep the existing flow.
  bool mergedSeriesPage = false;

  /// Resolve the addon that a Continue Watching title should route through.
  /// Prefers the stored source addon; falls back to any homepage addon, then a
  /// minimal placeholder so Play still works even if the addon is gone.
  StremioAddon addonForContinue(String? addonId) {
    if (addonId == _deps.nativeAddon().id) {
      return _deps.nativeAddon();
    }
    for (final addon in _boardSection.addonsById.values) {
      if (addon.sourceBindingKey == addonId ||
          addon.portableConfigurationKey == addonId) {
        return addon;
      }
    }
    if (addonId != null && _boardSection.addonsById.containsKey(addonId)) {
      return _boardSection.addonsById[addonId]!;
    }
    // "Any homepage addon" means a REAL catalog addon — the Trakt/Simkl list
    // rows that now lead _boardSection.homeSections carry only a placeholder addon (empty
    // baseUrl), which can't serve /meta or /stream.
    for (final s in _boardSection.homeSections) {
      if (!HomeBoardServices.isList(s) && s is! HomeCollectionSection) {
        return s.addon;
      }
    }
    return StremioAddon(
      id: addonId ?? 'continue_watching',
      name: 'Continue Watching',
      manifestUrl: '',
      baseUrl: '',
    );
  }

  /// Open a board-section item through the right pipeline for its source.
  /// Trakt list rows keep Trakt semantics (`isTraktSource` — status chips,
  /// Trakt-first resume label), Simkl rows open plainly (Discover's
  /// [_continuationPlayback.openSimklItem] routing), and real catalog sections route through their
  /// own addon exactly as before.
  void sectionOpenItem(
    CatalogSection section,
    StremioMeta item, {
    String? heroTag,
  }) {
    // A folder tile opens the folder's merged grid, never a detail page.
    if (section is HomeCollectionSection) {
      openCollectionFolder(section, item);
      return;
    }
    final list = HomeBoardServices.listOf(section);
    if (list != null) {
      if (list.simklList != null) {
        _continuationPlayback.openSimklItem(item, heroTag: heroTag);
        return;
      }
      _itemActions.openItem(
        item,
        addonForContinue(item.sourceAddon?.id),
        isTraktSource: list.isTrakt,
        isMdblistSource: list.isMdblist,
        heroTag: heroTag,
      );
      return;
    }
    _itemActions.openItem(item, section.addon, heroTag: heroTag);
  }

  /// Quick-play counterpart to [sectionOpenItem]. Trakt rows go through
  /// [_continuationPlayback.playTraktItem] (CW-cached resume, else catalog play with Trakt-first
  /// resume); Simkl rows play plainly like Discover's lists.
  void sectionQuickPlay(CatalogSection section, StremioMeta item) {
    // A folder tile has nothing to play — open it instead.
    if (section is HomeCollectionSection) {
      openCollectionFolder(section, item);
      return;
    }
    final list = HomeBoardServices.listOf(section);
    if (list != null) {
      if (list.isTrakt) {
        _continuationPlayback.playTraktItem(item);
      } else if (list.isMdblist) {
        _catalogActions.onCatalogPlay(
          item,
          addonForContinue(item.sourceAddon?.id),
          isMdblistSource: true,
        );
      } else {
        _continuationPlayback.playSimklItem(item);
      }
      return;
    }
    _catalogActions.onCatalogPlay(item, section.addon);
  }

  /// A folder tile on a collection row opens that folder's merged grid.
  void openCollectionFolder(HomeCollectionSection section, StremioMeta item) {
    final index = section.folderIndexOf(item);
    openCollectionScreen(section.collection, index < 0 ? 0 : index);
  }

  /// Push the folder browser on [folderIndex]. Items open through [_itemActions.openItem]
  /// with the addon that served them (the catalog fetch stamps
  /// `sourceAddon`), so the detail flow is the catalog rows' own.
  void openCollectionScreen(HomeCollection collection, int folderIndex) {
    final context = _deps.context();
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => withHomeExpandedCardSettings(
              CollectionFolderScreen(
                collection: collection,
                initialFolderIndex: folderIndex,
                fromHome: true,
                isTelevision: _deps.isTelevision(),
                onOpenItem: (item) => _itemActions.openItem(
                  item,
                  item.sourceAddon ?? addonForContinue(null),
                ),
                onQuickPlay: _catalogBadges.pikpakOnly
                    ? null
                    : (item) => _catalogActions.onCatalogPlay(
                        item,
                        item.sourceAddon ?? addonForContinue(null),
                      ),
              ),
            ),
          ),
        )
        .then((_) => _continuationReturn.afterSeeAllReturn());
  }

  /// Open a detail page requested by another tab (see [initState]). Builds a
  /// minimal Trakt-sourced [StremioMeta] from the handoff map and routes through
  /// the normal [_itemActions.openItem] path, so every action button behaves exactly as on
  /// the Home board. For a series it scrolls to the requested season/episode,
  /// and it returns to the origin tab when the detail closes.
  Future<void> openPendingCatalogDetail(Map<String, dynamic> data) async {
    final imdbId = data['imdbId'] as String?;
    if (imdbId == null || imdbId.isEmpty) return;
    // This can run before the board's async flags settle (they're kicked off
    // fire-and-forget in initState). Await the two that shape the detail so we
    // don't open the wrong thing: the merged-page flag (merged vs legacy screen
    // — only the merged one honours initialSeason/Episode, i.e. the scroll) and
    // Trakt auth (status chips + menu). Both are fast local reads, no network.
    await loadMergedSeriesFlag();
    await _integrations.refreshTraktAuthState();
    if (!_deps.mounted()) return;
    final type = (data['type'] as String?) == 'movie' ? 'movie' : 'series';
    final meta = StremioMeta(
      id: imdbId,
      imdbId: imdbId,
      type: type,
      name: (data['title'] as String?) ?? '',
      poster: data['poster'] as String?,
      year: (data['year'] as int?)?.toString(),
    );
    _itemActions.openItem(
      meta,
      addonForContinue(null),
      isTraktSource: true,
      initialSeason: data['season'] as int?,
      initialEpisode: data['episode'] as int?,
      returnToTabOnClose: data['originTab'] as int?,
    );
  }

  /// Load the experimental merged-series-page flag once on init.
  Future<void> loadMergedSeriesFlag() async {
    final on = await _deps.readMergedSeriesEnabled();
    if (_deps.mounted() && on != mergedSeriesPage) {
      _deps.setState(() => mergedSeriesPage = on);
    }
  }

  /// "Movies" / "Series" (etc.) tag for a catalog row, so two "Popular" rows
  /// (one movies, one series) are distinguishable. Null for unknown types.
  /// The row's provenance tag: which SOURCE fills it. Tracker list rows name
  /// their tracker; catalog rows name the addon. The content TYPE stopped
  /// being the tag when it moved into the heading itself ("Popular Movies" —
  /// see [CatalogSection.rowTitle]); the addon moved the other way, out of
  /// the heading it used to shout open ("Cinemeta: Popular") and into the
  /// quiet pill this feeds.
  String sectionTag(CatalogSection section) {
    if (section is HomeCollectionSection) return 'Collection';
    final list = HomeBoardServices.listOf(section);
    if (list != null) {
      return list.isTrakt
          ? 'Trakt'
          : list.isMdblist
          ? 'MDBList'
          : 'Simkl';
    }
    return section.addon.displayName;
  }

  /// Applies the Home presentation preference only to catalog/source
  /// provenance. Continue Watching type tags bypass this helper and remain
  /// visible so identically titled Movies/Series rows stay distinguishable.
  String? catalogSourceTag(CatalogSection section) =>
      _displaySection.hideHomeCatalogAddonNames ? null : sectionTag(section);

  /// Poster walls reached by expanding a Home row share Discover's card-detail
  /// controls. Search stays independent: its standalone result walls retain
  /// their normal labels and badges.
  Widget withHomeExpandedCardSettings(Widget child) {
    if (_deps.searchMode() || _deps.discoverMode()) return child;
    final settings = _deps.readCardSettings(isCurrent: () => _deps.mounted());
    return DiscoverCardSettingsScope(
      showTypeTags: settings.showTypeTags,
      showRatings: settings.showRatings,
      showTitles: settings.showTitles,
      child: child,
    );
  }

  late final seeAllNavigation = HomeSeeAllNavigation(
    isTelevision: () => _deps.isTelevision(),
    pikpakOnly: () => _catalogBadges.pikpakOnly,
    wrap: withHomeExpandedCardSettings,
    isBound: _catalogBadges.isBound,
    afterReturn: _continuationReturn.afterSeeAllReturn,
    afterTrackerReturn: () =>
        _continuationReturn.refreshAfterPlayback(trackers: true),
    traktItems: () => _continuationSection.traktAll,
    traktProgress: () =>
        _continuationSection.cwCardMaps(HomeContinuationKind.trakt).progress,
    simklItems: () => _continuationSection.simklAll,
    simklProgress: () => _continuationSection.simklProgress,
    openTraktItem: _continuationPlayback.openTraktItem,
    playTraktItem: _continuationPlayback.playTraktItem,
    openSimklItem: _continuationPlayback.openSimklItem,
    playSimklItem: _continuationPlayback.playSimklItem,
    openSimklCwItem: _continuationPlayback.openSimklCwItem,
    playSimklCwItem: _continuationPlayback.playSimklCwItem,
    openMdblist: (item) => _itemActions.openItem(
      item,
      addonForContinue(item.sourceAddon?.id),
      isMdblistSource: true,
    ),
    playMdblist: (item) => _catalogActions.onCatalogPlay(
      item,
      addonForContinue(item.sourceAddon?.id),
      isMdblistSource: true,
    ),
    openItem: (item, addon) => _itemActions.openItem(item, addon),
    playItem: _catalogActions.onCatalogPlay,
  );

  void openCatalogSeeAll(CatalogSection section) {
    final context = _deps.context();
    // Synthetic list/collection rows must never enter catalog pagination.
    final list = HomeBoardServices.listOf(section);
    if (list != null) {
      seeAllNavigation.openList(context, list);
    } else if (section is HomeCollectionSection) {
      openCollectionScreen(section.collection, 0);
    } else {
      seeAllNavigation.openCatalog(context, section);
    }
  }
}
