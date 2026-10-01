import 'package:flutter/widgets.dart';

import '../../features/discover/presentation/discover_panels.dart';
import '../../features/discover/presentation/discover_section.dart';
import '../../features/home/presentation/home_board_section.dart';
import '../../features/home/presentation/home_catalog_badges.dart';
import '../../features/home/presentation/home_continuation_playback.dart';
import '../../features/home/presentation/home_integration_section.dart';
import '../../features/home/presentation/home_rows_navigation.dart';
import '../../features/home/presentation/home_stage_rows.dart';
import '../../models/stremio_addon.dart';
import 'home_continuation_content_composition.dart';
import 'home_item_composition.dart';
import 'home_metadata_section.dart';

typedef DiscoverPanelCompositionDeps = ({
  bool Function() mounted,
  bool Function() isTelevision,
  bool mdblistEnabled,
});

/// Wires Discover panels to the route's existing Home content and actions.
class DiscoverPanelComposition {
  DiscoverPanelComposition(
    this._deps,
    this._metadata,
    this._integrations,
    this._badges,
    this._board,
    this._navigation,
    this._actions,
    this._continuation,
    this._playback,
  );

  final DiscoverPanelCompositionDeps _deps;
  final HomeMetadataSection _metadata;
  final HomeIntegrationSection _integrations;
  final HomeCatalogBadges _badges;
  final HomeBoardSection _board;
  final HomeRowsNavigation _navigation;
  final HomeItemComposition _actions;
  final HomeContinuationContent _continuation;
  final HomeContinuationPlayback _playback;

  Widget build(DiscoverSection section) => buildDiscoverPanels(
    selected: section.discSource,
    isTelevision: _deps.isTelevision(),
    sourceNode: section.discSourceNode,
    preferences: _metadata.metadataFeaturePolicy,
    mdblistEnabled: _deps.mdblistEnabled,
    mdblistAuthenticated: _integrations.isMdblistAuthenticated,
    addons: section.discAddons,
    onSelectSource: section.selectDiscoverSource,
    pikpakOnly: _badges.pikpakOnly,
    onItemFocused: section.onDiscFocused,
    isBound: (item) => _badges.isBound(item),
    findAddon: (id) => _board.addonsById[id],
    addonForContinue: (id) => _navigation.addonForContinue(id),
    onOpenCatalog: (item, addon, {isMdblistSource = false}) =>
        _actions.items.openItem(item, addon, isMdblistSource: isMdblistSource),
    onPlayCatalog: _actions.catalog.onCatalogPlay,
    traktItems: _continuation.section.traktAll,
    traktProgress: () =>
        _continuation.section.cwCardMaps(HomeContinuationKind.trakt).progress,
    onOpenTrakt: _playback.openTraktItem,
    onPlayTrakt: _playback.playTraktItem,
    simklItems: _continuation.section.simklAll,
    simklProgress: _continuation.section.simklProgress,
    onOpenSimkl: _playback.openSimklItem,
    onPlaySimkl: _playback.playSimklItem,
    onOpenSimklContinuation: _playback.openSimklCwItem,
    onPlaySimklContinuation: _playback.playSimklCwItem,
    mdblistList: section.discMdblistList,
    localItems: _continuation.section.cwAll,
    localProgress: (m) =>
        _continuation.section.cwCardProgress(HomeContinuationKind.local, m),
    onOpenLocal: _playback.openContinueItem,
    onPlayLocal: _playback.onContinuePlay,
    reloadLocal: () async {
      await _continuation.loading.loadContinueWatching();
      if (!_deps.mounted()) return const <StremioMeta>[];
      return List<StremioMeta>.of(_continuation.section.cwAll);
    },
  );
}
